import XCTest
@testable import HomeSignalCLI
@testable import HomeSignalCapture
@testable import HomeSignalCore
@testable import HomeSignalDisplay
@testable import HomeSignalInput
@testable import HomeSignalKit
@testable import HomeSignalLights
@testable import HomeSignalMirroring

final class HomeSignalTests: XCTestCase {
    func testExampleConfigMatchesFile() throws {
        let file = try String(contentsOfFile: "Config/config.example.toml", encoding: .utf8)
        XCTAssertEqual(file.trimmingCharacters(in: .whitespacesAndNewlines), ConfigText.example.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testExampleConfigParsesPlaceholders() throws {
        let config = try ConfigLoader.parse(ConfigText.example)
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.homekit.backend, "homekit")
        XCTAssertEqual(config.mirror.target, "TV")
        XCTAssertEqual(config.mirror.deviceID, "")
        XCTAssertEqual(config.displays.map(\.name), ["main", "external"])
        XCTAssertEqual(config.displays[0].width, 1920)
        XCTAssertEqual(config.simulated.devices.map(\.name), ["Lamp 1", "Lamp 2"])
        XCTAssertEqual(config.simulated.scenes, ["Scene A"])
        XCTAssertEqual(config.mirror.clicks.chooseContent.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(config.display.reconnectSeconds, 15, accuracy: 0.001)
    }

    func testConfigRejectsUnknownVersion() {
        XCTAssertThrowsError(try ConfigLoader.parse("version = 9\n"))
    }

    func testRepositoryHasNoPersonalFixtures() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path))
        let listURL = root.appendingPathComponent(".privacy-denylist")
        guard let list = try? String(contentsOf: listURL, encoding: .utf8) else {
            throw XCTSkip("No local .privacy-denylist file")
        }
        let phrases = list.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let worded: [String] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        var offenders: [String] = []
        while let item = enumerator.nextObject() as? URL {
            let path = item.path
            if path.contains("/.git/") || path.contains("/.build/") || path.hasSuffix("/.privacy-denylist") { continue }
            guard let text = try? String(contentsOf: item, encoding: .utf8) else { continue }
            for phrase in phrases where text.contains(phrase) {
                offenders.append("\(path): \(phrase)")
            }
            for pattern in worded {
                if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    offenders.append("\(path): \(pattern)")
                }
            }
        }
        XCTAssertEqual(offenders, [])
    }

    func testSHA256KnownVector() {
        XCTAssertEqual(
            ContentHash.sha256("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testHTMLEscapesScheduleRows() {
        let document = DisplayDocument(
            kind: DisplayKind.schedule,
            title: "Example day",
            rows: [ScheduleRow(time: "09:00", label: "Fish & Chips <lunch>")],
            background: "#000000",
            foreground: "#ffffff",
            accent: "#99ccff",
            messageSize: "10vw",
            titleSize: "6vw",
            rowSize: "3.2vw"
        )
        let html = DisplayRendering.renderGenerated(document)
        XCTAssertTrue(html.contains("Fish &amp; Chips &lt;lunch&gt;"))
        XCTAssertTrue(html.contains("09:00"))
        XCTAssertFalse(html.contains("<lunch>"))
    }

    func testCocoaFramesConvertToTopLeft() {
        let frames = [
            CocoaFrame(x: 1920, y: 0, width: 1280, height: 720),
            CocoaFrame(x: 0, y: 0, width: 1920, height: 1080),
        ]
        let displays = DisplayGeometry.fromCocoaFrames(frames)
        let main = displays.first { $0.primary }
        let external = displays.first { $0.name == "secondary" }
        XCTAssertEqual(main?.name, "main")
        XCTAssertEqual(main?.originX, 0)
        XCTAssertEqual(main?.originY, 0)
        XCTAssertEqual(external?.originX, 1920)
        XCTAssertEqual(external?.originY, 1080 - 720)
    }

    func testParkAndPanelFraction() throws {
        let displays = HomeSignalConfig.standard.displays
        let parked = try DisplayGeometry.park(displays: displays, display: "main", corner: "bottom-right", inset: 10)
        XCTAssertEqual(parked.x, 1910)
        XCTAssertEqual(parked.y, 1070)
        let external = try DisplayGeometry.park(displays: displays, display: "external", corner: "top-left", inset: 4)
        XCTAssertEqual(external.x, 1924)
        XCTAssertEqual(external.y, 4)
        let panel = PanelBounds(x: 100, y: 200, width: 400, height: 300)
        let point = try DisplayGeometry.resolve(.panelFraction(x: 0.5, y: 0.5), panel: panel, displays: displays)
        XCTAssertEqual(point.x, 300)
        XCTAssertEqual(point.y, 350)
    }

    func testKelvinMiredRoundTrip() {
        XCTAssertEqual(ColorTemperature.mireds(fromKelvin: 4000), 250)
        XCTAssertEqual(ColorTemperature.kelvin(fromMireds: 250), 4000)
    }

    func testNamedColorClearsTheOtherMode() throws {
        let warm = try NamedColor.patch(named: "warm")
        XCTAssertEqual(warm.colorTemperatureKelvin, 2700)
        XCTAssertTrue(warm.clearHueSaturation)
        var state = LightState(name: "Lamp 1", power: true, brightness: 10, hue: 20, saturation: 30)
        state = try state.applying(warm)
        XCTAssertNil(state.hue)
        XCTAssertEqual(state.colorTemperatureKelvin, 2700)
        XCTAssertEqual(state.brightness, 10)
    }

    func testBlinkRestoresPriorState() async throws {
        let backend = SimulatedLightBackend(config: HomeSignalConfig.standard.simulated)
        let prior = try await backend.getLight("Lamp 1")
        let service = BlinkService(sleeper: ImmediateSleeper())
        let params = BlinkParams(name: "Lamp 1", times: 2, color: "red", onMilliseconds: 50, offMilliseconds: 50)
        let dry = try await service.blink(backend, params: params, dryRun: true)
        XCTAssertEqual(dry.restored, prior)
        let afterDry = try await backend.getLight("Lamp 1")
        XCTAssertEqual(afterDry, prior)
        let live = try await service.blink(backend, params: params, dryRun: false)
        XCTAssertFalse(live.dryRun)
        let afterLive = try await backend.getLight("Lamp 1")
        XCTAssertTrue(LightStateMatch.restored(afterLive, matches: prior))
        XCTAssertEqual(afterLive.hue, prior.hue)
        XCTAssertEqual(afterLive.power, prior.power)
    }

    func testBlinkFailureStillRestores() async throws {
        let inner = SimulatedLightBackend(config: HomeSignalConfig.standard.simulated)
        let backend = FlakyLightBackend(inner: inner, failOnSet: 2)
        let prior = try await inner.getLight("Lamp 1")
        let service = BlinkService(sleeper: ImmediateSleeper())
        let params = BlinkParams(name: "Lamp 1", times: 2, color: "blue", onMilliseconds: 50, offMilliseconds: 0)
        do {
            _ = try await service.blink(backend, params: params, dryRun: false)
            XCTFail("expected the blink to stop early")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.code, "backend")
        }
        let restored = try await inner.getLight("Lamp 1")
        XCTAssertEqual(restored, prior)
    }

    func testMirrorScriptClicksTheResolvedName() {
        let script = MirrorScript.clickRoute("Example TV")
        XCTAssertTrue(script.contains("\"Example TV\""))
        XCTAssertTrue(script.contains("dump-routes") == false)
        XCTAssertTrue(MirrorScript.dumpWindow().contains("dump-window"))
        XCTAssertTrue(MirrorScript.clickModule(identifier: "controlcenter-screen-mirroring", description: "Screen Mirroring").contains("controlcenter-screen-mirroring"))
        XCTAssertTrue(MirrorScript.dumpMenuBar().contains("dump-menubar"))
    }

    func testMirrorConnectIsIdempotent() async throws {
        let mirror = SimulatedMirror()
        let first = try await mirror.connect(target: "TV", mode: "window", deviceID: "", dryRun: false, debugAX: false, debugFile: nil)
        XCTAssertTrue(first.changed)
        let second = try await mirror.connect(target: "TV", mode: "window", deviceID: "", dryRun: false, debugAX: false, debugFile: nil)
        XCTAssertFalse(second.changed)
        XCTAssertTrue(second.connected)
        let dry = await mirror.disconnect(target: "TV", dryRun: true, debugAX: false, debugFile: nil)
        XCTAssertTrue(dry.changed)
        let still = await mirror.status(target: "TV", debugAX: false, debugFile: nil)
        XCTAssertTrue(still.connected)
    }

    func testIPCRoundTrip() throws {
        let request = IPCRequest(id: "abc", method: IPCMethod.lightsGet, params: try LightNameParams(name: "Lamp 1").jsonValue(), dryRun: true)
        let data = try IPCCodec.encodeRequest(request)
        let decoded = try IPCCodec.decodeRequest(data)
        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.protocolVersion, 1)
    }

    func testShortcutsEncodeTheLightName() async throws {
        let runner = ScriptedRunner { arguments, input in
            XCTAssertEqual(arguments.first, "run")
            XCTAssertEqual(String(decoding: input ?? Data(), as: UTF8.self), "Lamp 1")
            let state = LightState(name: "Lamp 1", power: true, brightness: 40, hue: 30, saturation: 80)
            return CommandOutput(status: 0, stdout: try JSONEncoder().encode(state), stderr: Data())
        }
        let backend = ShortcutsLightBackend(names: HomeSignalConfig.standard.homekit.shortcuts, runner: runner)
        let state = try await backend.getLight("Lamp 1")
        XCTAssertEqual(state.brightness, 40)
    }

    func testHTTPSetUsesPUT() async throws {
        let sender = ScriptedHTTP { request in
            XCTAssertEqual(request.method, "PUT")
            XCTAssertTrue(request.url.path.contains("Lamp%201") || request.url.path.contains("Lamp 1"))
            XCTAssertEqual(request.bearer, "secret")
            let state = LightState(name: "Lamp 1", power: false, brightness: 40, hue: 30, saturation: 80)
            return HTTPResult(status: 200, body: try JSONEncoder().encode(state))
        }
        let backend = try HTTPLightBackend(
            config: HTTPConfig(baseURL: "http://127.0.0.1:8581", tokenEnv: "HOME_SIGNAL_HTTP_TOKEN"),
            sender: sender,
            environment: ["HOME_SIGNAL_HTTP_TOKEN": "secret"]
        )
        let state = try await backend.setLight("Lamp 1", LightPatch(power: false))
        XCTAssertFalse(state.power)
    }

    func testDescribeAndHelp() async throws {
        let sink = CollectingSink()
        let hooks = CLIHooks(config: .standard, sink: sink)
        let described = await CLI.run(["--json", "describe"], hooks: hooks)
        XCTAssertEqual(described, 0)
        XCTAssertTrue(sink.stdout().contains("\"command\" : \"describe\""))
        XCTAssertTrue(sink.stdout().contains("device blink"))
        let helpSink = CollectingSink()
        let helped = await CLI.run(["device", "blink", "--help"], hooks: CLIHooks(sink: helpSink))
        XCTAssertEqual(helped, 0)
        XCTAssertTrue(helpSink.stdout().contains("restore"))
        XCTAssertTrue(helpSink.stdout().contains("--dry-run"))
    }

    func testMissingAgentExits5() async {
        let sink = CollectingSink()
        let code = await CLI.run(
            ["--json", "--socket", "/tmp/home-signal-missing.sock", "device", "list"],
            hooks: CLIHooks(config: .standard, sink: sink)
        )
        XCTAssertEqual(code, 5)
        XCTAssertTrue(sink.stdout().contains("daemon_unavailable"))
    }

    func testEmptyDisplayDoesNotReplaceCustomHTML() async throws {
        let display = SimulatedDisplay()
        let runtime = makeRuntime(display: display)
        let page = "<html><head><title>Custom</title></head><body><p>Custom page</p></body></html>"
        let shown = try await show(runtime, kind: DisplayKind.html, html: page)
        XCTAssertEqual(shown.contentHash, ContentHash.sha256(page))
        XCTAssertEqual(shown.title, "Custom")
        XCTAssertTrue(shown.verified)
        XCTAssertTrue(shown.fullScreen)
        XCTAssertTrue(shown.onTarget)
        XCTAssertEqual(shown.target, "TV")
        XCTAssertFalse(shown.dryRun)
        XCTAssertTrue(shown.holdingWake)
        let kept = await display.presentedHTML()
        XCTAssertEqual(kept, page)
        XCTAssertFalse(page.contains("class=\"message\""))

        do {
            _ = try await show(runtime, kind: DisplayKind.message, message: "   ")
            XCTFail("empty message should fail")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.exitCode, 1)
        }
        let afterMessage = await display.presentedHTML()
        XCTAssertEqual(afterMessage, page)

        do {
            _ = try await show(runtime, kind: DisplayKind.html, html: "\n")
            XCTFail("empty html should fail")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.code, "usage")
        }
        let afterHTML = await display.presentedHTML()
        XCTAssertEqual(afterHTML, page)
    }

    func testDisplayMismatchFails() async throws {
        let runtime = makeRuntime(display: SubstitutingDisplay())
        do {
            _ = try await show(runtime, kind: DisplayKind.html, html: "<html><title>Custom</title><body>Custom page</body></html>")
            XCTFail("mismatch should fail")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.code, "display_mismatch")
            XCTAssertEqual(error.exitCode, 4)
        }
    }

    func testCLIRejectsEmptyMessageWithoutCallingAgent() async {
        let sink = CollectingSink()
        let client = RejectingAgent()
        let code = await CLI.run(
            ["display", "message", "   "],
            hooks: CLIHooks(client: client, config: .standard, sink: sink)
        )
        XCTAssertEqual(code, 1)
        XCTAssertFalse(client.called)
        XCTAssertTrue(sink.stderr().contains("Refusing"))
    }

    func testCLIHTMLFileRoundTrip() async throws {
        let page = "<html><head><title>Custom</title></head><body><p>Only this</p></body></html>\n"
        let path = "/tmp/hs-page-\(UUID().uuidString).html"
        try Data(page.utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let display = SimulatedDisplay()
        let runtime = makeRuntime(display: display)
        let stop = StopFlag()
        let socket = "/tmp/hs-\(UUID().uuidString).sock"
        let server = Task { try await AgentServer.serve(runtime: runtime, stop: stop, path: socket) }
        defer { stop.stop() }
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: socket) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let sink = CollectingSink()
        let code = await CLI.run(
            ["--json", "display", "html", "--file", path],
            hooks: CLIHooks(client: SocketAgentClient(socketPath: socket, timeoutSeconds: 10), config: .standard, sink: sink)
        )
        XCTAssertEqual(code, 0, sink.stdout() + sink.stderr())
        XCTAssertTrue(sink.stdout().contains(ContentHash.sha256(page)))
        XCTAssertTrue(sink.stdout().contains("\"verified\" : true"))
        XCTAssertTrue(sink.stdout().contains("Custom"))
        let shown = await display.presentedHTML()
        XCTAssertEqual(shown, page)
        let missing = await CLI.run(["display", "html"], hooks: CLIHooks(config: .standard, sink: CollectingSink()))
        XCTAssertEqual(missing, 1)
        stop.stop()
        _ = try await server.value
    }

    func testSocketRoundTrip() async throws {
        let stop = StopFlag()
        let config = HomeSignalConfig.standard
        let runtime = AgentRuntime(
            config: config,
            lights: SimulatedLightBackend(config: config.simulated),
            display: SimulatedDisplay(),
            mirror: SimulatedMirror(),
            input: SimulatedPointer(),
            capture: SimulatedCapture(),
            sleeper: ImmediateSleeper(),
            stop: stop
        )
        let path = "/tmp/hs-\(UUID().uuidString).sock"
        let server = Task {
            try await AgentServer.serve(runtime: runtime, stop: stop, path: path)
        }
        defer { stop.stop() }
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: path) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let sink = CollectingSink()
        let code = await CLI.run(
            ["--json", "device", "blink", "Lamp 1", "--times", "1", "--color", "green"],
            hooks: CLIHooks(client: SocketAgentClient(socketPath: path, timeoutSeconds: 10), config: config, sink: sink)
        )
        XCTAssertEqual(code, 0, sink.stdout() + sink.stderr())
        XCTAssertTrue(sink.stdout().contains("\"dryRun\" : false"))
        let status = CollectingSink()
        let mirrorCode = await CLI.run(
            ["--json", "mirror", "connect", "--target", "TV"],
            hooks: CLIHooks(client: SocketAgentClient(socketPath: path, timeoutSeconds: 10), config: config, sink: status)
        )
        XCTAssertEqual(mirrorCode, 0, status.stdout())
        let again = CollectingSink()
        let second = await CLI.run(
            ["--json", "mirror", "connect", "--target", "TV"],
            hooks: CLIHooks(client: SocketAgentClient(socketPath: path, timeoutSeconds: 10), config: config, sink: again)
        )
        XCTAssertEqual(second, 0)
        XCTAssertTrue(again.stdout().contains("\"changed\" : false"))
        stop.stop()
        _ = try await server.value
    }
}

private func makeRuntime(display: any DisplayChannel) -> AgentRuntime {
    let config = HomeSignalConfig.standard
    return AgentRuntime(
        config: config,
        lights: SimulatedLightBackend(config: config.simulated),
        display: display,
        mirror: SimulatedMirror(),
        input: SimulatedPointer(),
        capture: SimulatedCapture(),
        sleeper: ImmediateSleeper()
    )
}

private func show(_ runtime: AgentRuntime, kind: String, message: String? = nil, html: String? = nil) async throws -> DisplayShowResult {
    let config = HomeSignalConfig.standard
    let document = DisplayDocument(
        kind: kind,
        message: message,
        html: html,
        background: config.display.background,
        foreground: config.display.foreground,
        accent: config.display.accent,
        messageSize: config.display.messageSize,
        titleSize: config.display.titleSize,
        rowSize: config.display.rowSize
    )
    let response = await runtime.handle(
        IPCRequest(method: IPCMethod.displayShow, params: try DisplayShowParams(document: document, present: true).jsonValue())
    )
    if let error = response.error, !response.ok {
        throw error.error
    }
    guard let result = response.result else {
        throw HomeSignalError.backend("empty display response")
    }
    return try result.decode(DisplayShowResult.self)
}

actor SubstitutingDisplay: DisplayChannel {
    func show(html: String, kind: String, present: Bool) async throws -> DisplayReadback {
        _ = (html, present)
        let other = "<html><title>Other</title><body>Other</body></html>"
        return DisplayReadback(contentHash: ContentHash.sha256(other), title: "Other", kind: kind)
    }

    func readback() async -> DisplayReadback? { nil }

    func clear(present: Bool) async throws {
        _ = present
    }
}

final class RejectingAgent: AgentSending, @unchecked Sendable {
    var called = false

    func send(_ request: IPCRequest) async throws -> IPCResponse {
        called = true
        _ = request
        throw HomeSignalError.backend("agent should not be called")
    }
}

actor FlakyLightBackend: LightBackend {
    let backendID = "flaky"
    private let inner: SimulatedLightBackend
    private let failOnSet: Int
    private var sets = 0

    init(inner: SimulatedLightBackend, failOnSet: Int) {
        self.inner = inner
        self.failOnSet = failOnSet
    }

    func listDevices() async throws -> [LightDevice] { await inner.listDevices() }
    func getLight(_ name: String) async throws -> LightState { try await inner.getLight(name) }
    func setLight(_ name: String, _ patch: LightPatch) async throws -> LightState {
        sets += 1
        if sets == failOnSet { throw HomeSignalError.backend("forced") }
        return try await inner.setLight(name, patch)
    }
    func listScenes() async throws -> [Scene] { await inner.listScenes() }
    func runScene(_ name: String) async throws { try await inner.runScene(name) }
}

final class ScriptedRunner: CommandRunning, @unchecked Sendable {
    let body: @Sendable ([String], Data?) throws -> CommandOutput
    init(_ body: @escaping @Sendable ([String], Data?) throws -> CommandOutput) { self.body = body }
    func execute(launchPath: String, arguments: [String], input: Data?, timeoutSeconds: Double) async throws -> CommandOutput {
        _ = (launchPath, timeoutSeconds)
        return try body(arguments, input)
    }
}

final class ScriptedHTTP: HTTPSending, @unchecked Sendable {
    struct Call {
        var url: URL
        var method: String
        var bearer: String?
    }
    let body: @Sendable (Call) throws -> HTTPResult
    init(_ body: @escaping @Sendable (Call) throws -> HTTPResult) { self.body = body }
    func send(url: URL, method: String, body payload: Data?, bearer: String?) async throws -> HTTPResult {
        _ = payload
        return try self.body(Call(url: url, method: method, bearer: bearer))
    }
}
