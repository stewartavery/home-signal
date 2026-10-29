import ArgumentParser
import Foundation
import HomeSignalCore

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Print a JSON envelope on stdout. Errors use the same envelope and a non-zero exit code.")
    var json = false

    @Flag(name: .long, help: "Do not change lights, scenes, the display, mirroring, or the pointer. Display dry-run does not wake the display, reconnect, or show a page. Reads still run.")
    var dryRun = false

    @Option(name: .long, help: "Config file. Defaults to ~/.config/home-signal/config.toml.")
    var config: String?

    @Option(name: .long, help: "Unix socket for HomeSignalAgent. Overrides the config file.")
    var socket: String?
}

public protocol OutputSink: Sendable {
    func writeOut(_ text: String)
    func writeErr(_ text: String)
}

public final class StandardSink: OutputSink, @unchecked Sendable {
    public init() {}

    public func writeOut(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    public func writeErr(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}

public final class CollectingSink: OutputSink, @unchecked Sendable {
    private let lock = NSLock()
    private var out = ""
    private var err = ""

    public init() {}

    public func writeOut(_ text: String) {
        lock.lock()
        out += text
        lock.unlock()
    }

    public func writeErr(_ text: String) {
        lock.lock()
        err += text
        lock.unlock()
    }

    public func stdout() -> String {
        lock.lock()
        defer { lock.unlock() }
        return out
    }

    public func stderr() -> String {
        lock.lock()
        defer { lock.unlock() }
        return err
    }
}

public final class CLIHooks: @unchecked Sendable {
    public let client: (any AgentSending)?
    public let config: HomeSignalConfig?
    public let sink: any OutputSink

    public init(client: (any AgentSending)? = nil, config: HomeSignalConfig? = nil, sink: (any OutputSink)? = nil) {
        self.client = client
        self.config = config
        self.sink = sink ?? StandardSink()
    }
}

enum CLIRuntime {
    @TaskLocal static var hooks = CLIHooks()

    static func load(_ global: GlobalOptions) throws -> HomeSignalConfig {
        if global.config == nil, let config = hooks.config {
            return config
        }
        return try ConfigLoader.load(explicitPath: global.config)
    }

    static func client(_ global: GlobalOptions) throws -> any AgentSending {
        if let client = hooks.client {
            return client
        }
        let config = try load(global)
        let path = HomeSignalPaths.expand(global.socket ?? config.agent.socketPath)
        return SocketAgentClient(socketPath: path)
    }

    static func succeed(command: String, global: GlobalOptions, value: JSONValue) {
        emit(command: command, dryRun: global.dryRun, json: global.json, data: value, error: nil)
    }

    static func fail(command: String, dryRun: Bool, json: Bool, error: HomeSignalError) {
        emit(command: command, dryRun: dryRun, json: json, data: nil, error: error)
    }

    private static func emit(command: String, dryRun: Bool, json: Bool, data: JSONValue?, error: HomeSignalError?) {
        let sink = hooks.sink
        if json {
            let envelope: [String: JSONValue] = [
                "ok": .bool(error == nil),
                "command": .string(command),
                "dryRun": .bool(dryRun),
                "data": data ?? .null,
                "error": error.map { body($0) } ?? .null,
            ]
            let text = pretty(.object(envelope))
            if error == nil {
                sink.writeOut(text)
            } else {
                sink.writeOut(text)
            }
        } else if let error {
            var lines = ["error: \(error.message)"]
            if let hint = error.hint { lines.append("hint: \(hint)") }
            sink.writeErr(lines.joined(separator: "\n") + "\n")
        } else if let data {
            sink.writeOut(pretty(data))
        }
    }

    private static func body(_ error: HomeSignalError) -> JSONValue {
        var fields: [String: JSONValue] = [
            "code": .string(error.code),
            "message": .string(error.message),
            "exitCode": .int(Int(error.exitCode)),
        ]
        if let hint = error.hint {
            fields["hint"] = .string(hint)
        }
        if let step = error.step {
            fields["step"] = .string(step)
        }
        return .object(fields)
    }

    static func pretty(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder.pretty.encode(value), var text = String(data: data, encoding: .utf8) else {
            return "\n"
        }
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }
}

enum CLIArgv {
    static func normalize(_ args: [String]) -> [String] {
        var rest: [String] = []
        var globals: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--" {
                rest.append(contentsOf: args[index...])
                break
            } else if arg == "--json" || arg == "--dry-run" {
                globals.append(arg)
                index += 1
            } else if arg == "--config" || arg == "--socket" {
                globals.append(arg)
                index += 1
                if index < args.count {
                    globals.append(args[index])
                    index += 1
                }
            } else if arg.hasPrefix("--config=") || arg.hasPrefix("--socket=") {
                globals.append(arg)
                index += 1
            } else {
                rest.append(arg)
                index += 1
            }
        }
        return rest + globals
    }

    static func wantsJSON(_ args: [String]) -> Bool {
        args.contains("--json")
    }
}

enum IPCCall {
    static func perform(global: GlobalOptions, command: String, method: String, params: JSONValue = .object([:])) async throws {
        let result = try await send(global: global, method: method, params: params)
        CLIRuntime.succeed(command: command, global: global, value: result)
    }

    static func send(global: GlobalOptions, method: String, params: JSONValue = .object([:])) async throws -> JSONValue {
        let request = IPCRequest(method: method, params: params, dryRun: global.dryRun)
        let response: IPCResponse
        do {
            response = try await CLIRuntime.client(global).send(request)
        } catch let error as HomeSignalError {
            throw error
        } catch {
            let path = global.socket ?? HomeSignalPaths.defaultSocketPath()
            throw HomeSignalError.daemonUnavailable(path)
        }
        if let body = response.error, !response.ok {
            throw body.error
        }
        guard let result = response.result else {
            throw HomeSignalError.backend("The agent returned an empty response.")
        }
        return result
    }
}

func document(from config: HomeSignalConfig, kind: String, title: String?, message: String?, rows: [ScheduleRow], html: String? = nil) -> DisplayDocument {
    DisplayDocument(
        kind: kind,
        title: title,
        message: message,
        rows: rows,
        html: html,
        background: config.display.background,
        foreground: config.display.foreground,
        accent: config.display.accent,
        messageSize: config.display.messageSize,
        titleSize: config.display.titleSize,
        rowSize: config.display.rowSize
    )
}

func parseScheduleRow(_ row: String) throws -> ScheduleRow {
    guard let separator = row.firstIndex(of: "|") else {
        throw HomeSignalError.usage("Each --row value must look like \"09:00|Example\".")
    }
    let time = row[..<separator].trimmingCharacters(in: .whitespaces)
    let label = row[row.index(after: separator)...].trimmingCharacters(in: .whitespaces)
    guard !time.isEmpty, !label.isEmpty else {
        throw HomeSignalError.usage("Each --row value needs both a time and a label.")
    }
    return ScheduleRow(time: time, label: String(label))
}
