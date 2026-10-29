import Foundation
import HomeSignalCore

public struct ShortcutsLightBackend: LightBackend {
    public let backendID = "shortcuts"
    private let names: ShortcutsConfig
    private let runner: any CommandRunning

    public init(names: ShortcutsConfig, runner: any CommandRunning = ProcessCommandRunner()) {
        self.names = names
        self.runner = runner
    }

    public func listDevices() async throws -> [LightDevice] {
        try decode([LightDevice].self, try await run(names.listDevices, input: nil))
    }

    public func getLight(_ name: String) async throws -> LightState {
        try decode(LightState.self, try await run(names.getState, input: Data(name.utf8)))
    }

    public func setLight(_ name: String, _ patch: LightPatch) async throws -> LightState {
        let body = try JSONEncoder.ipc.encode(LightSetParams(name: name, patch: patch.resolved()))
        return try decode(LightState.self, try await run(names.setState, input: body))
    }

    public func listScenes() async throws -> [Scene] {
        try decode([Scene].self, try await run(names.listScenes, input: nil))
    }

    public func runScene(_ name: String) async throws {
        _ = try await run(names.runScene, input: Data(name.utf8))
    }

    private func run(_ name: String, input: Data?) async throws -> Data {
        let output = try await runner.execute(
            launchPath: "/usr/bin/shortcuts",
            arguments: ["run", name, "--input-path", "-", "--output-path", "-", "--output-type", "public.plain-text"],
            input: input,
            timeoutSeconds: 60
        )
        guard output.status == 0 else {
            let detail = output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HomeSignalError.backend(
                "Shortcut \(name) failed\(detail.isEmpty ? "." : ": \(detail)")",
                hint: "Install the shortcut and allow it to run without prompting. See README.md."
            )
        }
        return output.stdout
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let trimmed = data.trimmingWhitespace()
        if let object = try? JSONDecoder().decode(ShortcutFailure.self, from: trimmed), let message = object.error {
            throw HomeSignalError.backend(message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: trimmed)
        } catch {
            throw HomeSignalError.backend("Shortcut returned data that was not the expected JSON.")
        }
    }
}

private struct ShortcutFailure: Decodable {
    var error: String?
}

extension Data {
    fileprivate func trimmingWhitespace() -> Data {
        let text = String(decoding: self, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(text.utf8)
    }
}
