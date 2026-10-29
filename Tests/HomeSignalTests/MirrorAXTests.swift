import XCTest
@testable import HomeSignalCore
@testable import HomeSignalMirroring

final class MirrorAXTests: XCTestCase {
    func testNameMatchNormalizesApostrophesCaseAndWhitespace() {
        let routes = [
            MirrorRoute(name: "Example’s  TV", identifier: "", selected: false),
            MirrorRoute(name: "Other", identifier: "", selected: false),
        ]
        let match = MirrorAX.find(target: " example's tv ", deviceID: "", in: routes)
        XCTAssertEqual(match?.name, "Example’s  TV")
    }

    func testExactNameWinsOverCopySuffix() {
        let routes = [
            MirrorRoute(name: "Example TV (2)", identifier: "", selected: false),
            MirrorRoute(name: "Example TV", identifier: "", selected: true),
        ]
        XCTAssertEqual(MirrorAX.find(target: "Example TV", deviceID: "", in: routes)?.name, "Example TV")
        let onlyCopy = [routes[0]]
        XCTAssertEqual(MirrorAX.find(target: "Example TV", deviceID: "", in: onlyCopy)?.name, "Example TV (2)")
        XCTAssertEqual(MirrorAX.find(target: "Example TV (2)", deviceID: "", in: routes)?.name, "Example TV (2)")
    }

    func testComposedCharactersMatch() {
        let composed = "Cafe\u{0301} TV"
        let routes = [MirrorRoute(name: "Café TV", identifier: "", selected: false)]
        XCTAssertEqual(MirrorAX.find(target: composed, deviceID: "", in: routes)?.name, "Café TV")
    }

    func testMenuBarPrefersTopLevelScreenMirroring() {
        let both = MirrorAX.parse(lines([
            ax(role: "menu bar item", title: "Screen Mirroring", description: "Screen Mirroring"),
            ax(role: "menu bar item", title: "Control Center", description: "Control Center"),
        ]))
        XCTAssertEqual(MirrorAX.menuBarChoice(both), .screenMirroring(label: "Screen Mirroring"))
        let onlyCenter = MirrorAX.parse(lines([
            ax(role: "menu bar item", title: "Clock", description: "Clock"),
            ax(role: "menu bar item", title: "Control Center", description: "Control Center"),
        ]))
        XCTAssertEqual(MirrorAX.menuBarChoice(onlyCenter), .controlCenter(label: "Control Center"))
    }

    func testModuleMatchesIdentifierOrDescription() {
        let records = MirrorAX.parse(lines([
            ax(role: "button", identifier: "controlcenter-wifi", title: "Wi-Fi", description: "Wi-Fi"),
            ax(role: "button", identifier: "controlcenter-screen-mirroring", title: "", description: "Screen Mirroring"),
        ]))
        XCTAssertEqual(MirrorAX.screenMirroringModule(records)?.identifier, "controlcenter-screen-mirroring")
        let byLabel = MirrorAX.parse(lines([
            ax(role: "checkbox", identifier: "", title: "Screen Mirroring", description: "Screen Mirroring"),
        ]))
        XCTAssertEqual(MirrorAX.screenMirroringModule(byLabel)?.title, "Screen Mirroring")
    }

    func testRoutesSkipTheModuleAndKeepDeviceRows() {
        let records = MirrorAX.parse(lines([
            ax(role: "button", identifier: "controlcenter-screen-mirroring", description: "Screen Mirroring"),
            ax(role: "checkbox", description: "Example TV", value: "0"),
            ax(role: "checkbox", description: "Example Speaker", value: "1"),
        ]))
        let routes = MirrorAX.routes(records)
        XCTAssertEqual(routes.map(\.name), ["Example TV", "Example Speaker"])
        XCTAssertFalse(routes[0].selected)
        XCTAssertTrue(routes[1].selected)
    }

    func testPermissionErrorDetectsTheControlCenterWindowFailure() {
        XCTAssertTrue(MirrorAX.permissionProblem("System Events got an error: Can’t get window 1 of process \"ControlCenter\". (-1728)"))
        XCTAssertTrue(MirrorAX.permissionProblem("osascript is not allowed assistive access"))
        XCTAssertFalse(MirrorAX.permissionProblem("AirPlay target not found: Example TV"))
        let syntax = "64:72: syntax error: Expected end of line but found identifier. (-2741)"
        XCTAssertTrue(MirrorAX.syntaxProblem(syntax))
        XCTAssertFalse(MirrorAX.permissionProblem(syntax))
        let bug = MirrorAX.automationFailure(syntax)
        XCTAssertEqual(bug.code, "script_bug")
        XCTAssertEqual(bug.exitCode, 4)
        XCTAssertFalse(bug.hint?.contains("Grant Accessibility") == true)
        XCTAssertEqual(MirrorScript.appleString("Example's \"TV\""), "\"Example's \\\"TV\\\"\"")
    }

    func testNotFoundListsTheNamesThatWereRead() {
        let error = HomeSignalError.airPlayNotFound(target: "Example TV", seen: ["Other", "Example Speaker"])
        XCTAssertEqual(error.exitCode, 3)
        XCTAssertTrue(error.message.contains("Other"))
        XCTAssertTrue(error.message.contains("Example Speaker"))
        XCTAssertTrue(error.message.contains("Example TV"))
    }

    func testDNSSDParsesInstanceNames() {
        let output = """
        Browsing for _airplay._tcp.local.
        Timestamp     A/R    Flags  if Domain  Service Type   Instance Name
        1:00:00.000  Add        2  10 local.   _airplay._tcp. Example TV
        1:00:01.000  Add        2  10 local.   _airplay._tcp. Example Speaker
        """
        XCTAssertEqual(DNSSDText.instanceNames(output), ["Example TV", "Example Speaker"])
    }

    func testControlCenterPathReadsRoutesAndClicksTheMatchedRow() async throws {
        let runner = QueueRunner(outputs: [
            ok(axLine(role: "menu bar item", title: "Control Center", description: "Control Center")),
            ok("clicked"),
            ok(axLine(role: "button", identifier: "controlcenter-screen-mirroring", description: "Screen Mirroring")),
            ok("clicked"),
            ok(""),
            ok(axLine(role: "checkbox", description: "Example TV (2)", value: "0")),
            ok("clicked"),
        ])
        let mirror = SystemEventsMirror(
            config: HomeSignalConfig.standard.mirror,
            displays: { [] },
            runner: runner,
            clicker: { _ in },
            sleeper: ImmediateSleeper()
        )
        let status = try await mirror.connect(target: "Example TV", mode: "display", deviceID: "", dryRun: false, debugAX: true, debugFile: nil)
        XCTAssertTrue(status.connected)
        XCTAssertTrue(status.changed)
        XCTAssertTrue(runner.scripts.contains { $0.contains("dump-menubar") })
        XCTAssertTrue(runner.scripts.contains { $0.contains("click-module") })
        XCTAssertTrue(runner.scripts.contains { $0.contains("Example TV (2)") })
    }

    func testMissingAutomationIsAPermissionError() async throws {
        let runner = QueueRunner(outputs: [
            CommandOutput(status: 1, stdout: Data(), stderr: Data("Can’t get window 1 of process \"ControlCenter\". (-1728)".utf8)),
        ])
        let mirror = SystemEventsMirror(
            config: HomeSignalConfig.standard.mirror,
            displays: { [] },
            runner: runner,
            clicker: { _ in },
            sleeper: ImmediateSleeper()
        )
        do {
            _ = try await mirror.status(target: "Example TV", debugAX: false, debugFile: nil)
            XCTFail("expected a permission error")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.code, "permission")
            XCTAssertEqual(error.exitCode, 6)
        }
    }

    func testHomeKitGateRefusesAnUnentitledAgent() {
        let missing = HomeKitBackendGate.refusal(moduleAvailable: true, entitlementPresent: false)
        XCTAssertEqual(missing?.exitCode, 6)
        XCTAssertTrue(missing?.message.contains("com.apple.developer.homekit") == true)
        XCTAssertTrue(missing?.hint?.contains("shortcuts") == true)
        XCTAssertNil(HomeKitBackendGate.refusal(moduleAvailable: true, entitlementPresent: true))
        let xml = "<key>com.apple.developer.homekit</key>\n<true/>"
        XCTAssertTrue(HomeKitBackendGate.plistGrantsHomeKit(xml))
        XCTAssertFalse(HomeKitBackendGate.plistGrantsHomeKit("<key>com.apple.developer.homekit</key><false/>"))
    }

    func testDebugFileKeepsEarlierStepsWhenALaterScriptFails() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("hs-ax-\(UUID().uuidString).txt").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let runner = QueueRunner(outputs: [
            ok(axLine(role: "menu bar item", title: "Control Center", description: "Control Center")),
            CommandOutput(status: 1, stdout: Data(), stderr: Data("64:72: syntax error: Expected end of line but found identifier. (-2741)".utf8)),
        ])
        let mirror = SystemEventsMirror(
            config: HomeSignalConfig.standard.mirror,
            displays: { [] },
            runner: runner,
            clicker: { _ in },
            sleeper: ImmediateSleeper()
        )
        do {
            _ = try await mirror.list(discover: false, debugAX: true, debugFile: path)
            XCTFail("expected a script bug")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.code, "script_bug")
            XCTAssertEqual(error.exitCode, 4)
            XCTAssertTrue(error.hint?.contains("[menubar]") == true)
        }
        let saved = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(saved.contains("[menubar]"))
        XCTAssertTrue(saved.contains("Control Center"))
        XCTAssertTrue(saved.contains("[error]"))
        XCTAssertTrue(saved.contains("-2741"))
    }

    func testGeneratedAppleScriptsCompile() throws {
        #if os(macOS)
        for script in MirrorScript.generated {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hs-\(UUID().uuidString).applescript")
            try Data(script.utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hs-\(UUID().uuidString).scpt")
            defer { try? FileManager.default.removeItem(at: output) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
            process.arguments = ["-o", output.path, url.path]
            let stderr = Pipe()
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            let detail = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0, detail + "\n" + script)
        }
        #else
        throw XCTSkip("osacompile is only available on macOS")
        #endif
    }

    func testInstallScriptUsesAUserPrefixAndDoesNotCallSudo() throws {
        let script = try String(contentsOfFile: "Scripts/install.sh", encoding: .utf8)
        XCTAssertTrue(script.contains("PREFIX"))
        XCTAssertTrue(script.contains(".local"))
        XCTAssertTrue(script.contains("PATH"))
        XCTAssertFalse(script.contains("sudo"))
        XCTAssertFalse(script.contains("/usr/local/bin"))
    }
}

private func ax(role: String, identifier: String = "", title: String = "", description: String = "", value: String = "") -> String {
    axLine(role: role, identifier: identifier, title: title, description: description, value: value)
}

private func axLine(role: String, identifier: String = "", title: String = "", description: String = "", value: String = "") -> String {
    "1\t\(role)\t\t\(identifier)\t\(title)\t\(description)\t\(value)\n"
}

private func lines(_ rows: [String]) -> String {
    rows.joined()
}

private func ok(_ text: String) -> CommandOutput {
    CommandOutput(status: 0, stdout: Data(text.utf8), stderr: Data())
}

private final class QueueRunner: CommandRunning, @unchecked Sendable {
    var outputs: [CommandOutput]
    var scripts: [String] = []

    init(outputs: [CommandOutput]) {
        self.outputs = outputs
    }

    func execute(launchPath: String, arguments: [String], input: Data?, timeoutSeconds: Double) async throws -> CommandOutput {
        _ = (launchPath, input, timeoutSeconds)
        scripts.append(arguments.joined(separator: "\n"))
        guard !outputs.isEmpty else {
            return CommandOutput(status: 1, stdout: Data(), stderr: Data("no more output".utf8))
        }
        return outputs.removeFirst()
    }
}
