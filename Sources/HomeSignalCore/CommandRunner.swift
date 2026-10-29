import Foundation

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func collect(launchPath: String, arguments: [String], timeoutSeconds: Double) async -> CommandOutput {
        let path = launchPath
        let args = arguments
        let timeout = timeoutSeconds
        return await Task.detached(priority: .userInitiated) {
            ProcessCommandRunner.collecting(launchPath: path, arguments: args, timeoutSeconds: timeout)
        }.value
    }

    public func execute(launchPath: String, arguments: [String], input: Data?, timeoutSeconds: Double) async throws -> CommandOutput {
        let path = launchPath
        let args = arguments
        let stdin = input
        let timeout = timeoutSeconds
        return try await Task.detached(priority: .userInitiated) {
            try ProcessCommandRunner.blocking(launchPath: path, arguments: args, input: stdin, timeoutSeconds: timeout)
        }.value
    }

    private static func collecting(launchPath: String, arguments: [String], timeoutSeconds: Double) -> CommandOutput {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else {
            return CommandOutput(status: 127, stdout: Data(), stderr: Data("missing \(launchPath)".utf8))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return CommandOutput(status: 127, stdout: Data(), stderr: Data(String(describing: error).utf8))
        }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        return CommandOutput(
            status: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }

    private static func blocking(launchPath: String, arguments: [String], input: Data?, timeoutSeconds: Double) throws -> CommandOutput {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else {
            throw HomeSignalError.unsupported(
                "Executable not found: \(launchPath).",
                hint: "This command needs macOS tools such as /usr/bin/shortcuts or /usr/bin/osascript."
            )
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin
        if let input {
            try stdin.fileHandleForWriting.write(contentsOf: input)
        }
        try stdin.fileHandleForWriting.close()
        try process.run()
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw HomeSignalError.timeout("\(launchPath) exceeded \(timeoutSeconds)s.")
        }
        return CommandOutput(
            status: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }
}
