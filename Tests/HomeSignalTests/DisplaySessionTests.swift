import XCTest
@testable import HomeSignalCLI
@testable import HomeSignalCapture
@testable import HomeSignalCore
@testable import HomeSignalDisplay
@testable import HomeSignalInput
@testable import HomeSignalKit
@testable import HomeSignalLights

final class DisplaySessionTests: XCTestCase {
    func testMatchUsesNameOrDeviceIDAndDoesNotUseAnotherScreen() {
        let local = AttachedDisplay(name: "Local", deviceID: "1", width: 800, height: 600, originX: 0, originY: 0, primary: true)
        let panel = AttachedDisplay(name: "Panel", deviceID: "10", width: 800, height: 600, originX: 800, originY: 0, primary: false)
        let screens = [local, panel]
        XCTAssertEqual(DisplayMatch.find(DisplayTarget(name: "Panel", deviceID: ""), in: screens)?.name, "Panel")
        XCTAssertEqual(DisplayMatch.find(DisplayTarget(name: "Other", deviceID: "10"), in: screens)?.name, "Panel")
        XCTAssertEqual(DisplayMatch.find(DisplayTarget(name: "Panel", deviceID: "route-1"), in: screens)?.name, "Panel")
        XCTAssertNil(DisplayMatch.find(DisplayTarget(name: "Missing", deviceID: "nope"), in: screens))
    }

    func testShowWakesHoldsAndVerifiesTheTarget() async throws {
        let power = SimulatedDisplayPower()
        let screens = MutableDisplays([
            AttachedDisplay(name: "Local", deviceID: "1", width: 800, height: 600, originX: 0, originY: 0, primary: true),
            AttachedDisplay(name: "Panel", deviceID: "10", width: 800, height: 600, originX: 800, originY: 0, primary: false),
        ])
        let mirror = LinkingMirror(displays: screens, screen: panelScreen)
        let placer = ScriptedPlacer()
        let runtime = makeRuntime(power: power, screens: screens, mirror: mirror, placer: placer)
        let shown = try await show(runtime, html: page("Hello"))
        XCTAssertTrue(shown.verified)
        XCTAssertTrue(shown.fullScreen)
        XCTAssertTrue(shown.onTarget)
        XCTAssertEqual(shown.screen, "Panel")
        XCTAssertEqual(shown.target, "Panel")
        XCTAssertTrue(shown.holdingWake)
        let wakes = await power.wakeCount
        let holding = await power.isHolding()
        let connects = await mirror.connects
        let placed = await placer.placedTargets
        XCTAssertEqual(wakes, 1)
        XCTAssertTrue(holding)
        XCTAssertEqual(connects, 0)
        XCTAssertEqual(placed, ["Panel"])
    }

    func testReconnectsWhenTheTargetIsMissingThenVerifies() async throws {
        let screens = MutableDisplays([
            AttachedDisplay(name: "Local", deviceID: "1", width: 800, height: 600, originX: 0, originY: 0, primary: true),
        ])
        let mirror = LinkingMirror(displays: screens, screen: panelScreen)
        let placer = ScriptedPlacer()
        let runtime = makeRuntime(screens: screens, mirror: mirror, placer: placer)
        let shown = try await show(runtime, html: page("Hello"), target: "Panel", deviceID: "route-1")
        XCTAssertTrue(shown.verified)
        XCTAssertEqual(shown.screen, "Panel")
        let connects = await mirror.connects
        let names = await mirror.connectNames
        let ids = await mirror.connectIDs
        XCTAssertEqual(connects, 1)
        XCTAssertEqual(names, ["Panel"])
        XCTAssertEqual(ids, ["route-1"])
        let again = try await show(runtime, html: page("Again"), target: "Panel", deviceID: "route-1")
        XCTAssertTrue(again.verified)
        let connectsAgain = await mirror.connects
        XCTAssertEqual(connectsAgain, 1)
    }

    func testMissingTargetFailsTheReconnectStepAndDoesNotShow() async throws {
        let power = SimulatedDisplayPower()
        let screens = MutableDisplays([
            AttachedDisplay(name: "Local", deviceID: "1", width: 800, height: 600, originX: 0, originY: 0, primary: true),
        ])
        let mirror = LinkingMirror(displays: screens, screen: panelScreen, addOnConnect: false)
        let placer = ScriptedPlacer()
        let runtime = makeRuntime(power: power, screens: screens, mirror: mirror, placer: placer, reconnectSeconds: 0)
        let error = await showError(runtime, html: page("Hello"), target: "Panel")
        XCTAssertEqual(error.code, "display_step_failed")
        XCTAssertEqual(error.step, "reconnect")
        XCTAssertEqual(error.exitCode, 7)
        XCTAssertTrue(error.message.contains("Step reconnect failed"))
        XCTAssertTrue(error.message.contains("Panel"))
        XCTAssertTrue(error.message.contains("Local"))
        let placed = await placer.placedTargets
        let html = await placer.html()
        let holding = await power.isHolding()
        XCTAssertEqual(placed, [])
        XCTAssertNil(html)
        XCTAssertFalse(holding)
    }

    func testFailedRefreshKeepsThePageThatWasAlreadyConfirmed() async throws {
        let power = SimulatedDisplayPower()
        let screens = MutableDisplays([panelScreen])
        let mirror = LinkingMirror(displays: screens, screen: panelScreen, addOnConnect: false)
        let placer = ScriptedPlacer()
        let runtime = makeRuntime(power: power, screens: screens, mirror: mirror, placer: placer, reconnectSeconds: 0)
        let first = page("First")
        _ = try await show(runtime, html: first, target: "Panel")
        await screens.removeAll()
        let error = await showError(runtime, html: page("Second"), target: "Panel")
        XCTAssertEqual(error.step, "reconnect")
        let html = await placer.html()
        let holding = await power.isHolding()
        XCTAssertEqual(html, first)
        XCTAssertTrue(holding)
    }

    func testWakeFailureIsNamedAndDoesNotReconnect() async throws {
        let power = SimulatedDisplayPower()
        await power.setFailWake()
        let mirror = LinkingMirror(displays: MutableDisplays([]), screen: panelScreen)
        let placer = ScriptedPlacer()
        let runtime = makeRuntime(power: power, screens: MutableDisplays([]), mirror: mirror, placer: placer, reconnectSeconds: 0)
        let error = await showError(runtime, html: page("Hello"), target: "Panel")
        XCTAssertEqual(error.step, "wake")
        XCTAssertTrue(error.message.contains("Step wake failed"))
        let connects = await mirror.connects
        let placed = await placer.placedTargets
        XCTAssertEqual(connects, 0)
        XCTAssertEqual(placed, [])
    }

    func testWrongScreenAndNotFullScreenFailVerify() async throws {
        let screens = MutableDisplays([panelScreen])
        let mirror = LinkingMirror(displays: screens, screen: panelScreen)
        let wrong = ScriptedPlacer()
        await wrong.setScreenName("Local")
        let runtime = makeRuntime(screens: screens, mirror: mirror, placer: wrong, reconnectSeconds: 0)
        let wrongScreen = await showError(runtime, html: page("Hello"), target: "Panel")
        XCTAssertEqual(wrongScreen.step, "verify")
        XCTAssertTrue(wrongScreen.message.contains("Local"))
        XCTAssertTrue(wrongScreen.message.contains("Refusing to use another screen"))
        let cleared = await wrong.html()
        XCTAssertNil(cleared)

        let cropped = ScriptedPlacer()
        await cropped.setFullScreen(false)
        let again = makeRuntime(screens: MutableDisplays([panelScreen]), mirror: LinkingMirror(displays: MutableDisplays([panelScreen]), screen: panelScreen), placer: cropped)
        let notFull = await showError(again, html: page("Hello"), target: "Panel")
        XCTAssertEqual(notFull.step, "verify")
        XCTAssertTrue(notFull.message.contains("not full screen"))
    }

    func testHashMismatchNamesVerify() async throws {
        let screens = MutableDisplays([panelScreen])
        let placer = ScriptedPlacer()
        await placer.setHashOverride("different")
        let runtime = makeRuntime(screens: screens, mirror: LinkingMirror(displays: screens, screen: panelScreen), placer: placer)
        let error = await showError(runtime, html: page("Hello"), target: "Panel")
        XCTAssertEqual(error.code, "display_mismatch")
        XCTAssertEqual(error.step, "verify")
        XCTAssertTrue(error.message.contains("Step verify failed"))
        let html = await placer.html()
        XCTAssertNil(html)
    }

    func testDryRunDoesNotWakeReconnectOrShow() async throws {
        let power = SimulatedDisplayPower()
        let screens = MutableDisplays([
            AttachedDisplay(name: "Local", deviceID: "1", width: 800, height: 600, originX: 0, originY: 0, primary: true),
        ])
        let mirror = LinkingMirror(displays: screens, screen: panelScreen)
        let placer = ScriptedPlacer()
        let runtime = makeRuntime(power: power, screens: screens, mirror: mirror, placer: placer)
        let response = await showResponse(runtime, html: page("Hello"), dryRun: true, target: "Panel")
        XCTAssertTrue(response.ok)
        let shown = try XCTUnwrap(response.result).decode(DisplayShowResult.self)
        XCTAssertFalse(shown.verified)
        XCTAssertTrue(shown.dryRun)
        XCTAssertFalse(shown.onTarget)
        XCTAssertEqual(shown.target, "Panel")
        XCTAssertEqual(shown.attached, ["Local"])
        let wakes = await power.wakeCount
        let connects = await mirror.connects
        let html = await placer.html()
        XCTAssertEqual(wakes, 0)
        XCTAssertEqual(connects, 0)
        XCTAssertNil(html)
    }

    func testClearReleasesTheAssertionAndShutdownDoesToo() async throws {
        let power = SimulatedDisplayPower()
        let screens = MutableDisplays([panelScreen])
        let placer = ScriptedPlacer()
        let runtime = makeRuntime(power: power, screens: screens, mirror: LinkingMirror(displays: screens, screen: panelScreen), placer: placer)
        _ = try await show(runtime, html: page("Hello"), target: "Panel")
        let cleared = await runtime.handle(IPCRequest(method: IPCMethod.displayClear, params: try PresentParams(present: true).jsonValue()))
        XCTAssertTrue(cleared.ok)
        let clearResult = try XCTUnwrap(cleared.result).decode(DisplayShowResult.self)
        XCTAssertFalse(clearResult.verified)
        XCTAssertFalse(clearResult.holdingWake)
        let clearedHTML = await placer.html()
        let released = await power.isHolding()
        XCTAssertNil(clearedHTML)
        XCTAssertFalse(released)

        _ = try await show(runtime, html: page("Again"), target: "Panel")
        let heldAgain = await power.isHolding()
        XCTAssertTrue(heldAgain)
        let dry = await runtime.handle(IPCRequest(method: IPCMethod.displayClear, params: try PresentParams(present: true).jsonValue(), dryRun: true))
        XCTAssertTrue(dry.ok)
        let stillHeld = await power.isHolding()
        let stillShown = await placer.html()
        XCTAssertTrue(stillHeld)
        XCTAssertNotNil(stillShown)
        let stopped = await runtime.handle(IPCRequest(method: IPCMethod.systemShutdown))
        XCTAssertTrue(stopped.ok)
        let afterStop = await power.isHolding()
        let afterHTML = await placer.html()
        XCTAssertFalse(afterStop)
        XCTAssertNil(afterHTML)
    }

    func testEmptyContentDoesNotWake() async throws {
        let power = SimulatedDisplayPower()
        let runtime = makeRuntime(
            power: power,
            screens: MutableDisplays([panelScreen]),
            mirror: LinkingMirror(displays: MutableDisplays([panelScreen]), screen: panelScreen),
            placer: ScriptedPlacer()
        )
        let config = HomeSignalConfig.standard
        let document = DisplayDocument(
            kind: DisplayKind.message,
            message: "   ",
            background: config.display.background,
            foreground: config.display.foreground,
            accent: config.display.accent,
            messageSize: config.display.messageSize,
            titleSize: config.display.titleSize,
            rowSize: config.display.rowSize
        )
        let response = await runtime.handle(IPCRequest(method: IPCMethod.displayShow, params: try DisplayShowParams(document: document, present: true).jsonValue()))
        XCTAssertEqual(response.error?.exitCode, 1)
        let wakes = await power.wakeCount
        XCTAssertEqual(wakes, 0)
    }

    func testSignalWindowSourceDoesNotFallBackToTheMainScreen() throws {
        let source = try String(contentsOfFile: "Sources/HomeSignalDisplay/DisplayChannels.swift", encoding: .utf8)
        XCTAssertFalse(source.contains("NSScreen.main"))
        XCTAssertFalse(source.contains("pickScreen"))
    }

    func testReconnectSecondsMustBePositive() {
        XCTAssertThrowsError(try ConfigLoader.parse("version = 1\n[display]\nreconnect_seconds = 0\n"))
    }

    func testDisplayShowParamsOmitTheTarget() throws {
        let json = "{\"document\":{\"kind\":\"html\",\"rows\":[],\"background\":\"#000\",\"foreground\":\"#fff\",\"accent\":\"#fff\",\"messageSize\":\"1\",\"titleSize\":\"1\",\"rowSize\":\"1\"},\"present\":true}"
        let params = try JSONDecoder().decode(DisplayShowParams.self, from: Data(json.utf8))
        XCTAssertNil(params.targetName)
        XCTAssertNil(params.targetDeviceID)
        XCTAssertTrue(params.present)
    }

    func testHomeBlinkRestoresAndReportsMissingOrUncontrollable() async throws {
        let backend = SimulatedLightBackend(config: HomeSignalConfig.standard.simulated)
        let service = BlinkService(sleeper: ImmediateSleeper())
        let prior = try await backend.getLight("Lamp 1")
        let dry = try await service.blinkAccessory(backend, accessory: "Lamp 1", times: 2, intervalSeconds: 0.4, color: "green", dryRun: true)
        XCTAssertEqual(dry.prior, prior)
        let afterDry = try await backend.getLight("Lamp 1")
        XCTAssertEqual(afterDry, prior)
        let live = try await service.blinkAccessory(backend, accessory: "Lamp 1", times: 1, intervalSeconds: 0.05, color: "green", dryRun: false)
        XCTAssertFalse(live.dryRun)
        let afterLive = try await backend.getLight("Lamp 1")
        XCTAssertTrue(LightStateMatch.restored(afterLive, matches: prior))

        do {
            _ = try await service.blinkAccessory(backend, accessory: "Missing", times: 1, intervalSeconds: 0.4, color: "amber", dryRun: false)
            XCTFail("missing accessory should fail")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.code, "not_found")
            XCTAssertEqual(error.exitCode, 3)
            XCTAssertTrue(error.message.contains("accessory"))
            XCTAssertTrue(error.message.contains("Missing"))
        }

        let mixed = ListingBackend(inner: backend, extra: [LightDevice(name: "Sensor 1", type: "sensor")])
        do {
            _ = try await service.blinkAccessory(mixed, accessory: "Sensor 1", times: 1, intervalSeconds: 0.4, color: "amber", dryRun: true)
            XCTFail("sensor should not blink")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.code, "not_controllable")
            XCTAssertEqual(error.exitCode, 6)
            XCTAssertTrue(error.message.contains("Sensor 1"))
        }
        let still = try await backend.getLight("Lamp 1")
        XCTAssertEqual(still, prior)
    }

    func testHomeBlinkCLISendsTheAccessoryAndInterval() async throws {
        let agent = RecordingAgent()
        let sink = CollectingSink()
        let code = await CLI.run(
            ["--json", "home", "blink", "--accessory", "Lamp 1", "--times", "2", "--interval", "0.5", "--dry-run"],
            hooks: CLIHooks(client: agent, config: .standard, sink: sink)
        )
        XCTAssertEqual(code, 0, sink.stdout() + sink.stderr())
        let request = try XCTUnwrap(agent.request)
        XCTAssertEqual(request.method, IPCMethod.homeBlink)
        XCTAssertTrue(request.dryRun)
        let params = try request.params.decode(HomeBlinkParams.self)
        XCTAssertEqual(params.accessory, "Lamp 1")
        XCTAssertEqual(params.times, 2)
        XCTAssertEqual(params.intervalSeconds, 0.5, accuracy: 0.001)
        let help = CollectingSink()
        let helped = await CLI.run(["home", "blink", "--help"], hooks: CLIHooks(sink: help))
        XCTAssertEqual(helped, 0)
        XCTAssertTrue(help.stdout().contains("--accessory"))
        XCTAssertTrue(help.stdout().contains("--interval"))
        XCTAssertTrue(help.stdout().contains("restore"))
        let described = CollectingSink()
        _ = await CLI.run(["--json", "describe"], hooks: CLIHooks(config: .standard, sink: described))
        XCTAssertTrue(described.stdout().contains("home blink"))
        let missing = await CLI.run(["home", "blink", "--times", "1"], hooks: CLIHooks(sink: CollectingSink()))
        XCTAssertEqual(missing, 64)
    }

    func testDisplayCLIPassesTheTargetAndDryRun() async throws {
        let agent = RecordingAgent()
        let sink = CollectingSink()
        let code = await CLI.run(
            ["display", "message", "Example notice", "--target", "Panel", "--device-id", "route-1", "--dry-run"],
            hooks: CLIHooks(client: agent, config: .standard, sink: sink)
        )
        XCTAssertEqual(code, 0, sink.stdout() + sink.stderr())
        let request = try XCTUnwrap(agent.request)
        XCTAssertTrue(request.dryRun)
        let params = try request.params.decode(DisplayShowParams.self)
        XCTAssertEqual(params.targetName, "Panel")
        XCTAssertEqual(params.targetDeviceID, "route-1")
        XCTAssertEqual(params.document.message, "Example notice")
    }
}

private let panelScreen = AttachedDisplay(name: "Panel", deviceID: "10", width: 800, height: 600, originX: 800, originY: 0, primary: false)

private func page(_ text: String) -> String {
    "<html><head><title>\(text)</title></head><body><p>\(text)</p></body></html>"
}

private func makeRuntime(
    power: SimulatedDisplayPower = SimulatedDisplayPower(),
    screens: MutableDisplays,
    mirror: LinkingMirror,
    placer: ScriptedPlacer,
    reconnectSeconds: Double = 15
) -> AgentRuntime {
    var config = HomeSignalConfig.standard
    config.display.reconnectSeconds = reconnectSeconds
    config.mirror.target = "Panel"
    return AgentRuntime(
        config: config,
        lights: SimulatedLightBackend(config: config.simulated),
        display: SimulatedDisplay(),
        mirror: mirror,
        input: SimulatedPointer(),
        capture: SimulatedCapture(),
        sleeper: ImmediateSleeper(),
        power: power,
        screens: screens,
        placer: placer
    )
}

private func show(
    _ runtime: AgentRuntime,
    html: String,
    dryRun: Bool = false,
    target: String? = nil,
    deviceID: String? = nil
) async throws -> DisplayShowResult {
    let response = await showResponse(runtime, html: html, dryRun: dryRun, target: target, deviceID: deviceID)
    if let error = response.error, !response.ok {
        throw error.error
    }
    return try XCTUnwrap(response.result).decode(DisplayShowResult.self)
}

private func showError(
    _ runtime: AgentRuntime,
    html: String,
    target: String? = nil
) async -> HomeSignalError {
    let response = await showResponse(runtime, html: html, target: target)
    return response.error?.error ?? HomeSignalError.backend("expected a failure")
}

private func showResponse(
    _ runtime: AgentRuntime,
    html: String,
    dryRun: Bool = false,
    target: String? = nil,
    deviceID: String? = nil
) async -> IPCResponse {
    let config = HomeSignalConfig.standard
    let document = DisplayDocument(
        kind: DisplayKind.html,
        html: html,
        background: config.display.background,
        foreground: config.display.foreground,
        accent: config.display.accent,
        messageSize: config.display.messageSize,
        titleSize: config.display.titleSize,
        rowSize: config.display.rowSize
    )
    let params = DisplayShowParams(document: document, present: true, targetName: target, targetDeviceID: deviceID)
    return await runtime.handle(IPCRequest(method: IPCMethod.displayShow, params: (try? params.jsonValue()) ?? .object([:]), dryRun: dryRun))
}

actor MutableDisplays: AttachedDisplayListing {
    private var items: [AttachedDisplay]
    init(_ items: [AttachedDisplay]) { self.items = items }
    func attachedDisplays() async -> [AttachedDisplay] { items }
    func add(_ item: AttachedDisplay) { items.append(item) }
    func removeAll() { items = [] }
}

actor LinkingMirror: MirrorChannel {
    let displays: MutableDisplays
    let screen: AttachedDisplay
    var addOnConnect: Bool
    private(set) var connects = 0
    private(set) var connectNames: [String] = []
    private(set) var connectIDs: [String] = []

    init(displays: MutableDisplays, screen: AttachedDisplay, addOnConnect: Bool = true) {
        self.displays = displays
        self.screen = screen
        self.addOnConnect = addOnConnect
    }

    func status(target: String, debugAX: Bool) async throws -> MirrorStatus {
        _ = debugAX
        return MirrorStatus(target: target, connected: false, changed: false)
    }

    func connect(target: String, mode: String, deviceID: String, dryRun: Bool, debugAX: Bool) async throws -> MirrorStatus {
        _ = debugAX
        connects += 1
        connectNames.append(target)
        connectIDs.append(deviceID)
        if !dryRun, addOnConnect {
            await displays.add(screen)
        }
        return MirrorStatus(target: target, connected: true, mode: mode, changed: true)
    }

    func list(discover: Bool, debugAX: Bool) async throws -> MirrorListResult {
        _ = (discover, debugAX)
        return MirrorListResult(controlCenter: [], discovered: [], routes: [], accessibility: [])
    }

    func disconnect(target: String, dryRun: Bool, debugAX: Bool) async throws -> MirrorStatus {
        _ = debugAX
        _ = dryRun
        return MirrorStatus(target: target, connected: false, changed: true)
    }
}

actor ScriptedPlacer: DisplayPlacing {
    private let inner = SimulatedDisplay()
    private(set) var placedTargets: [String] = []
    private var fullScreen = true
    private var screenName: String?
    private var hashOverride: String?

    func setScreenName(_ name: String) { screenName = name }
    func setFullScreen(_ value: Bool) { fullScreen = value }
    func setHashOverride(_ value: String) { hashOverride = value }

    func place(html: String, kind: String, present: Bool, target: DisplayTarget) async throws -> PlacementReport {
        placedTargets.append(target.name)
        let readback = try await inner.show(html: html, kind: kind, present: present)
        let shown = hashOverride.map { DisplayReadback(contentHash: $0, title: "Other", kind: kind) } ?? readback
        return PlacementReport(
            readback: shown,
            screenName: screenName ?? target.name,
            deviceID: target.deviceID,
            fullScreen: fullScreen
        )
    }

    func dismiss() async {
        await inner.clear(present: true)
    }

    func html() async -> String? {
        await inner.presentedHTML()
    }
}

actor ListingBackend: LightBackend {
    let backendID = "listing"
    let inner: SimulatedLightBackend
    let extra: [LightDevice]
    init(inner: SimulatedLightBackend, extra: [LightDevice]) {
        self.inner = inner
        self.extra = extra
    }
    func listDevices() async throws -> [LightDevice] { await inner.listDevices() + extra }
    func getLight(_ name: String) async throws -> LightState { try await inner.getLight(name) }
    func setLight(_ name: String, _ patch: LightPatch) async throws -> LightState { try await inner.setLight(name, patch) }
    func listScenes() async throws -> [Scene] { await inner.listScenes() }
    func runScene(_ name: String) async throws { try await inner.runScene(name) }
}

final class RecordingAgent: AgentSending, @unchecked Sendable {
    var request: IPCRequest?
    func send(_ request: IPCRequest) async throws -> IPCResponse {
        self.request = request
        return .success(id: request.id, result: .object(["recorded": .bool(true)]))
    }
}
