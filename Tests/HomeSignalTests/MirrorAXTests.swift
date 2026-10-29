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
        let records = MirrorAX.parse(lines(controlCenterModules()))
        XCTAssertEqual(MirrorAX.screenMirroringModule(records)?.identifier, "controlcenter-screen-mirroring")
        let withoutModule = records.filter { $0.identifier != "controlcenter-screen-mirroring" }
        XCTAssertNil(MirrorAX.screenMirroringModule(withoutModule))
        let byLabel = MirrorAX.parse(lines([
            ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "controlcenter-wifi", description: "toggle button"),
            ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "module-fallback", title: "Screen Mirroring", description: "toggle button"),
        ]))
        XCTAssertEqual(MirrorAX.screenMirroringModule(byLabel)?.identifier, "module-fallback")
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

    func testRouteNamesComeFromIdentifierWhenLabelsAreGeneric() {
        let records = MirrorAX.parse(lines(controlCenterModules() + screenMirroringRoutes()))
        let routes = MirrorAX.routes(records)
        XCTAssertEqual(routes.map(\.name), ["Example TV", "Example Speaker"])
        XCTAssertEqual(routes.map(\.identifier), [
            "screen-mirroring-device-Example TV",
            "screen-mirroring-receiver-Example Speaker",
        ])
        XCTAssertEqual(routes.map(\.selected), [false, true])
        XCTAssertFalse(routes.contains { $0.name == "toggle button" || $0.name == "button" })
        XCTAssertEqual(MirrorAX.find(target: "Example TV", deviceID: "", in: routes)?.identifier, "screen-mirroring-device-Example TV")
        let labels = MirrorAX.labels(records)
        XCTAssertFalse(labels.contains("toggle button"))
        XCTAssertFalse(labels.contains("button"))
        let dump = MirrorAX.format(records)
        XCTAssertTrue(dump.contains("id=controlcenter-screen-mirroring"))
        XCTAssertTrue(dump.contains("id=screen-mirroring-device-Example TV"))
        XCTAssertEqual(
            MirrorAX.nameFromIdentifier("screen-mirroring-audio-Example Panel"),
            "Example Panel"
        )
        XCTAssertNil(MirrorAX.nameFromIdentifier("screen-mirroring-header"))
        XCTAssertNil(MirrorAX.nameFromIdentifier("wifi-network-ExampleNet"))
        XCTAssertNil(MirrorAX.nameFromIdentifier("screen-mirroring-preferences"))
        XCTAssertNil(MirrorAX.nameFromIdentifier(exampleTVRow))
        XCTAssertNil(MirrorAX.meaningful("missing value"))
        XCTAssertNil(MirrorAX.routeName("missing value"))
    }

    func testDeviceListNamesComeFromAttributesNotTheIdentifier() {
        let early = MirrorAX.deviceRoutes(in: preferencesOnlyTree())
        XCTAssertEqual(early.checkboxCount, 0)
        XCTAssertTrue(early.routes.isEmpty)

        let read = MirrorAX.deviceRoutes(in: deviceListTree())
        XCTAssertEqual(read.checkboxCount, 2)
        XCTAssertEqual(read.unnamed, [])
        XCTAssertEqual(read.routes.map(\.name), ["Example TV", "Example Speaker"])
        XCTAssertEqual(read.routes.map(\.identifier), [exampleTVRow, exampleSpeakerRow])
        XCTAssertEqual(read.routes.map(\.selected), [false, true])
        XCTAssertFalse(read.routes.contains { $0.name == "missing value" || $0.name.contains("00000000") })

        let help = MirrorAX.deviceRoutes(in: axEl("AXGroup", ["AXIdentifier": "screen-mirroring-device-list"], [
            axEl("AXCheckBox", [
                "AXIdentifier": exampleTVRow,
                "AXDescription": "toggle button",
                "AXTitle": "missing value",
                "AXHelp": "Example TV",
                "AXValue": "0",
            ]),
        ]))
        XCTAssertEqual(help.routes.map(\.name), ["Example TV"])

        let custom = MirrorAX.deviceRoutes(in: axEl("AXGroup", ["AXIdentifier": "screen-mirroring-device-list"], [
            axEl("AXCheckBox", [
                "AXIdentifier": exampleTVRow,
                "AXDescription": "toggle button",
                "AXTitle": "missing value",
                "AXCustomContent": "label=ignored; value=Example TV",
                "AXValue": "0",
            ]),
        ]))
        XCTAssertEqual(custom.routes.map(\.name), ["Example TV"])

        let ordered = MirrorAX.deviceRoutes(in: rowOrderTree())
        XCTAssertEqual(ordered.routes.map(\.name), ["Example TV", "Example Speaker"])

        let unnamed = MirrorAX.deviceRoutes(in: unnamedTree())
        XCTAssertEqual(unnamed.checkboxCount, 1)
        XCTAssertTrue(unnamed.routes.isEmpty)
        XCTAssertEqual(unnamed.unnamed, ["row 1 id=\(exampleTVRow)"])

        let dump = MirrorAX.formatAttributes(deviceListTree())
        XCTAssertTrue(dump.contains("AXTitle=missing value"))
        XCTAssertTrue(dump.contains("AXLabel=Example Speaker"))
        XCTAssertTrue(dump.contains("AXHelp="))
        XCTAssertTrue(dump.contains("AXAttributedDescription="))
        XCTAssertTrue(dump.contains("AXCustomContent="))
        XCTAssertTrue(dump.contains("AXValue=Example TV"))
        XCTAssertTrue(dump.contains("AXIdentifier=\(exampleTVRow)"))
        XCTAssertTrue(dump.contains("screen-mirroring-device-list"))
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
        let debugFile = FileManager.default.temporaryDirectory.appendingPathComponent("hs-ax-\(UUID().uuidString).txt").path
        defer { try? FileManager.default.removeItem(atPath: debugFile) }
        let ax = QueueAX([preferencesOnlyTree(), deviceListTree()])
        let runner = QueueRunner(outputs: [
            ok(axLine(role: "menu bar item", title: "Control Center", description: "Control Center")),
            ok("clicked"),
            ok(lines(controlCenterModules())),
            ok("clicked"),
            ok("clicked"),
        ])
        let mirror = SystemEventsMirror(
            config: HomeSignalConfig.standard.mirror,
            displays: { [] },
            runner: runner,
            clicker: { _ in },
            sleeper: ImmediateSleeper(),
            ax: ax
        )
        let status = try await mirror.connect(target: "Example TV", mode: "display", deviceID: "", dryRun: false, debugAX: true, debugFile: debugFile)
        XCTAssertTrue(status.connected)
        XCTAssertTrue(status.changed)
        XCTAssertGreaterThan(ax.calls, 1)
        let moduleClick = runner.scripts.first { $0.contains("click-module") }
        XCTAssertTrue(moduleClick?.contains("set wantedID to \"controlcenter-screen-mirroring\"") == true)
        XCTAssertTrue(moduleClick?.contains("set wantedDesc to \"\"") == true)
        XCTAssertFalse(moduleClick?.contains("controlcenter-wifi") == true)
        let routeClick = runner.scripts.first { $0.contains("click-route") }
        XCTAssertTrue(routeClick?.contains("set wantedID to \"\(exampleTVRow)\"") == true)
        XCTAssertTrue(routeClick?.contains("set wantedName to \"Example TV\"") == true)
        XCTAssertFalse(routeClick?.contains("set wantedName to \"missing value\"") == true)
        XCTAssertFalse(routeClick?.contains("set wantedID to \"screen-mirroring-preferences\"") == true)
        let saved = try String(contentsOfFile: debugFile, encoding: .utf8)
        XCTAssertTrue(saved.contains("id=controlcenter-screen-mirroring"))
        XCTAssertTrue(saved.contains("[routes]"))
        XCTAssertTrue(saved.contains("AXIdentifier=\(exampleTVRow)"))
        XCTAssertTrue(saved.contains("AXTitle=missing value"))
        XCTAssertTrue(saved.contains("AXValue=Example TV"))
        XCTAssertTrue(saved.contains("screen-mirroring-preferences"))
    }

    func testMirrorListOmitsGenericControlLabels() async throws {
        let runner = QueueRunner(outputs: [
            ok(axLine(role: "menu bar item", title: "Control Center", description: "Control Center")),
            ok("clicked"),
            ok(lines(controlCenterModules())),
            ok("clicked"),
        ])
        let mirror = SystemEventsMirror(
            config: HomeSignalConfig.standard.mirror,
            displays: { [] },
            runner: runner,
            clicker: { _ in },
            sleeper: ImmediateSleeper(),
            ax: QueueAX([preferencesOnlyTree(), deviceListTree()])
        )
        let listed = try await mirror.list(discover: false, debugAX: true, debugFile: nil)
        XCTAssertEqual(listed.controlCenter, ["Example TV", "Example Speaker"])
        XCTAssertFalse(listed.controlCenter.contains("missing value"))
        XCTAssertFalse(listed.controlCenter.contains("toggle button"))
        XCTAssertFalse(listed.controlCenter.contains("button"))
        XCTAssertFalse(listed.controlCenter.contains("preferences"))
        let routes = listed.accessibility.filter { $0.step == "routes" }.map(\.tree).joined(separator: "\n")
        XCTAssertTrue(routes.contains("AXLabel="))
        XCTAssertTrue(routes.contains("AXHelp="))
        XCTAssertTrue(routes.contains("AXCustomContent="))
        XCTAssertTrue(routes.contains("AXAttributedDescription="))
    }

    func testMirrorListWaitsForDeviceRowsAndRefusesMissingValue() async throws {
        let debugFile = FileManager.default.temporaryDirectory.appendingPathComponent("hs-ax-\(UUID().uuidString).txt").path
        defer { try? FileManager.default.removeItem(atPath: debugFile) }
        let runner = QueueRunner(outputs: [
            ok(axLine(role: "menu bar item", title: "Control Center", description: "Control Center")),
            ok("clicked"),
            ok(lines(controlCenterModules())),
            ok("clicked"),
        ])
        let mirror = SystemEventsMirror(
            config: HomeSignalConfig.standard.mirror,
            displays: { [] },
            runner: runner,
            clicker: { _ in },
            sleeper: ImmediateSleeper(),
            ax: QueueAX([unnamedTree()])
        )
        do {
            _ = try await mirror.list(discover: false, debugAX: true, debugFile: debugFile)
            XCTFail("expected an unreadable name")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.code, "backend")
            XCTAssertEqual(error.exitCode, 4)
            XCTAssertTrue(error.message.contains("no name"))
            XCTAssertTrue(error.message.contains("row 1"))
            XCTAssertFalse(error.message.contains("missing value"))
        }
        let saved = try String(contentsOfFile: debugFile, encoding: .utf8)
        XCTAssertTrue(saved.contains("AXTitle=missing value"))
        XCTAssertTrue(saved.contains("AXLabel="))
        XCTAssertTrue(saved.contains("AXHelp="))
    }

    func testPreferencesButtonIsNotAReceiverRow() async throws {
        let runner = QueueRunner(outputs: [
            ok(axLine(role: "menu bar item", title: "Control Center", description: "Control Center")),
            ok("clicked"),
            ok(lines(controlCenterModules())),
            ok("clicked"),
        ])
        let mirror = SystemEventsMirror(
            config: HomeSignalConfig.standard.mirror,
            displays: { [] },
            runner: runner,
            clicker: { _ in },
            sleeper: ImmediateSleeper(),
            ax: QueueAX([preferencesOnlyTree()])
        )
        do {
            _ = try await mirror.list(discover: false, debugAX: false, debugFile: nil)
            XCTFail("expected a timeout")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.code, "timeout")
            XCTAssertEqual(error.exitCode, 7)
            XCTAssertTrue(error.message.contains("screen-mirroring-preferences"))
            XCTAssertFalse(error.message.contains("missing value"))
        }
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

private let exampleTVRow = "screen-mirroring-device-AirPlay:00000000-0000-4000-8000-000000000001"
private let exampleSpeakerRow = "screen-mirroring-device-AirPlay:00000000-0000-4000-8000-000000000002"

private func preferencesOnlyTree() -> AXElement {
    axEl("AXWindow", ["AXTitle": "Control Center", "AXSubrole": "AXSystemDialog"], [
        axEl("AXGroup", [:], [
            axEl("AXButton", [
                "AXIdentifier": "screen-mirroring-preferences",
                "AXDescription": "button",
                "AXTitle": "missing value",
            ]),
            axEl("AXStaticText", [
                "AXIdentifier": "screen-mirroring-header",
                "AXTitle": "Screen Mirroring",
                "AXValue": "Screen Mirroring",
            ]),
        ]),
    ])
}

private func deviceListTree() -> AXElement {
    axEl("AXWindow", ["AXTitle": "Control Center", "AXSubrole": "AXSystemDialog"], [
        axEl("AXGroup", [:], [
            axEl("AXButton", [
                "AXIdentifier": "screen-mirroring-preferences",
                "AXDescription": "button",
                "AXTitle": "missing value",
            ]),
            axEl("AXStaticText", [
                "AXIdentifier": "screen-mirroring-header",
                "AXTitle": "Screen Mirroring",
                "AXValue": "Screen Mirroring",
            ]),
            axEl("AXScrollArea", [:], [
                axEl("AXGroup", ["AXIdentifier": "screen-mirroring-device-list"], [
                    axEl("AXHeading", [:]),
                    axEl("AXCheckBox", [
                        "AXSubrole": "AXToggle",
                        "AXIdentifier": exampleTVRow,
                        "AXDescription": "toggle button",
                        "AXTitle": "missing value",
                        "AXLabel": "",
                        "AXHelp": "",
                        "AXAttributedDescription": "",
                        "AXValue": "0",
                        "AXCustomContent": "",
                    ], [
                        axEl("AXStaticText", ["AXValue": "Example TV", "AXTitle": "missing value"]),
                    ]),
                    axEl("AXCheckBox", [
                        "AXSubrole": "AXToggle",
                        "AXIdentifier": exampleSpeakerRow,
                        "AXDescription": "toggle button",
                        "AXTitle": "missing value",
                        "AXLabel": "Example Speaker",
                        "AXHelp": "",
                        "AXAttributedDescription": "",
                        "AXValue": "1",
                        "AXCustomContent": "",
                    ]),
                ]),
            ]),
        ]),
    ])
}

private func rowOrderTree() -> AXElement {
    axEl("AXGroup", ["AXIdentifier": "screen-mirroring-device-list"], [
        axEl("AXStaticText", ["AXValue": "Example TV"]),
        axEl("AXCheckBox", [
            "AXIdentifier": exampleTVRow,
            "AXDescription": "toggle button",
            "AXTitle": "missing value",
            "AXValue": "0",
        ]),
        axEl("AXStaticText", ["AXValue": "Example Speaker"]),
        axEl("AXCheckBox", [
            "AXIdentifier": exampleSpeakerRow,
            "AXDescription": "toggle button",
            "AXTitle": "missing value",
            "AXValue": "1",
        ]),
    ])
}

private func unnamedTree() -> AXElement {
    axEl("AXGroup", ["AXIdentifier": "screen-mirroring-device-list"], [
        axEl("AXCheckBox", [
            "AXIdentifier": exampleTVRow,
            "AXDescription": "toggle button",
            "AXTitle": "missing value",
            "AXLabel": "",
            "AXHelp": "",
            "AXAttributedDescription": "",
            "AXValue": "0",
            "AXCustomContent": "",
        ]),
    ])
}

private func axEl(_ role: String, _ attributes: [String: String] = [:], _ children: [AXElement] = []) -> AXElement {
    var stored = attributes
    stored["AXRole"] = role
    return AXElement(role: role, attributes: stored, children: children)
}

private final class QueueAX: ScreenMirroringReading, @unchecked Sendable {
    private var items: [AXElement]
    private var last: AXElement
    private(set) var calls = 0

    init(_ items: [AXElement]) {
        self.items = items
        self.last = items.last ?? AXElement(role: "AXWindow", attributes: [:], children: [])
    }

    func snapshot() async throws -> AXElement {
        calls += 1
        if items.isEmpty { return last }
        let next = items.removeFirst()
        last = next
        return next
    }
}

private func controlCenterModules() -> [String] {
    [
        ax(role: "AXWindow", subrole: "AXSystemDialog", title: "Control Center"),
        ax(role: "AXGroup", subrole: "AXHostingView", depth: 2),
        ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "controlcenter-wifi", description: "toggle button", depth: 3),
        ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "controlcenter-bluetooth", description: "toggle button", depth: 3),
        ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "controlcenter-airdrop", description: "toggle button", depth: 3),
        ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "controlcenter-focus-modes", description: "toggle button", depth: 3),
        ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "controlcenter-display", description: "toggle button", depth: 3),
        ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "controlcenter-airplay", description: "toggle button", depth: 3),
        ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "controlcenter-screen-mirroring", description: "toggle button", depth: 3),
        ax(role: "AXButton", description: "button", depth: 3),
    ]
}

private func screenMirroringRoutes() -> [String] {
    [
        ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "screen-mirroring-header", description: "toggle button"),
        ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "screen-mirroring-device-Example TV", description: "toggle button", value: "0"),
        ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "screen-mirroring-receiver-Example Speaker", description: "toggle button", value: "1"),
        ax(role: "AXCheckBox", subrole: "AXToggle", identifier: "wifi-network-ExampleNet", description: "toggle button", value: "0"),
        ax(role: "AXButton", description: "button"),
    ]
}

private func ax(
    role: String,
    subrole: String = "",
    identifier: String = "",
    title: String = "",
    description: String = "",
    value: String = "",
    depth: Int = 1
) -> String {
    axLine(role: role, subrole: subrole, identifier: identifier, title: title, description: description, value: value, depth: depth)
}

private func axLine(
    role: String,
    subrole: String = "",
    identifier: String = "",
    title: String = "",
    description: String = "",
    value: String = "",
    depth: Int = 1
) -> String {
    "\(depth)\t\(role)\t\(subrole)\t\(identifier)\t\(title)\t\(description)\t\(value)\n"
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
