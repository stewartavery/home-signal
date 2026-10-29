import HomeSignalCore

public struct DNSSDAirPlayBrowser: AirPlayDiscovering {
    private let runner: ProcessCommandRunner

    public init(runner: ProcessCommandRunner = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func discover(timeoutSeconds: Double) async -> [String] {
        let output = await runner.collect(
            launchPath: "/usr/bin/dns-sd",
            arguments: ["-B", "_airplay._tcp", "local."],
            timeoutSeconds: timeoutSeconds
        )
        return DNSSDText.instanceNames(output.stdoutText)
    }
}
