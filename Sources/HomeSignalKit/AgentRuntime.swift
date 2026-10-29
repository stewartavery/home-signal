import Foundation
import HomeSignalCore

public actor AgentRuntime {
    private let lights: any LightBackend
    private let display: any DisplayChannel
    private let mirror: any MirrorChannel
    private let input: any InputChannel
    private let capture: any CaptureChannel
    private let config: HomeSignalConfig
    private var displays: [DisplayBounds]
    private let blink: BlinkService
    private let stop: StopFlag
    private let log = Log(category: "runtime")

    public init(
        config: HomeSignalConfig,
        displays: [DisplayBounds]? = nil,
        lights: any LightBackend,
        display: any DisplayChannel,
        mirror: any MirrorChannel,
        input: any InputChannel,
        capture: any CaptureChannel,
        sleeper: any Sleeper = TaskSleeper(),
        stop: StopFlag = StopFlag()
    ) {
        self.config = config
        self.displays = displays ?? config.displays
        self.lights = lights
        self.display = display
        self.mirror = mirror
        self.input = input
        self.capture = capture
        self.blink = BlinkService(sleeper: sleeper)
        self.stop = stop
    }

    public func handleData(_ data: Data) async -> Data {
        let response: IPCResponse
        do {
            let request = try IPCCodec.decodeRequest(data)
            response = await handle(request)
        } catch {
            response = .failure(id: "decode", error: .usage("Could not decode the request."))
        }
        return (try? IPCCodec.encodeResponse(response)) ?? Data()
    }

    public func handle(_ request: IPCRequest) async -> IPCResponse {
        if request.protocolVersion != HomeSignalVersion.protocolVersion {
            return .failure(
                id: request.id,
                error: .usage("Protocol version \(request.protocolVersion) is not supported. This agent speaks version \(HomeSignalVersion.protocolVersion).")
            )
        }
        log.info("\(request.method) \(request.id) dryRun=\(request.dryRun)")
        do {
            let result = try await dispatch(request)
            return .success(id: request.id, result: result)
        } catch let error as HomeSignalError {
            log.error("\(request.method) \(error.code): \(error.message)")
            return .failure(id: request.id, error: error)
        } catch {
            log.error("\(request.method) \(error)")
            return .failure(id: request.id, error: .backend(String(describing: error)))
        }
    }

    private func dispatch(_ request: IPCRequest) async throws -> JSONValue {
        switch request.method {
        case IPCMethod.capabilities:
            return try CapabilityReport(
                protocolVersion: HomeSignalVersion.protocolVersion,
                agentVersion: HomeSignalVersion.current,
                backend: lights.backendID,
                methods: IPCMethod.all,
                channels: ["lights", "scenes", "display", "mirror", "input", "capture"]
            ).jsonValue()
        case IPCMethod.lightsList:
            return try await lights.listDevices().jsonValue()
        case IPCMethod.lightsGet:
            let params = try request.params.decode(LightNameParams.self)
            return try await lights.getLight(params.name).jsonValue()
        case IPCMethod.lightsSet:
            let params = try request.params.decode(LightSetParams.self)
            if request.dryRun {
                let current = try await lights.getLight(params.name)
                return try current.applying(params.patch).jsonValue()
            }
            return try await lights.setLight(params.name, params.patch).jsonValue()
        case IPCMethod.lightsBlink:
            let params = try request.params.decode(BlinkParams.self)
            return try await blink.blink(lights, params: params, dryRun: request.dryRun).jsonValue()
        case IPCMethod.scenesList:
            return try await lights.listScenes().jsonValue()
        case IPCMethod.scenesRun:
            let params = try request.params.decode(LightNameParams.self)
            if request.dryRun {
                return try SceneRunResult(name: params.name, ran: false).jsonValue()
            }
            try await lights.runScene(params.name)
            return try SceneRunResult(name: params.name, ran: true).jsonValue()
        case IPCMethod.displayShow:
            let params = try request.params.decode(DisplayShowParams.self)
            return try await showPrepared(params.document, present: params.present, dryRun: request.dryRun)
        case IPCMethod.displayStatus:
            return try await display.readback().jsonValue()
        case IPCMethod.displayClear:
            let params = try request.params.decode(PresentParams.self)
            return try await showPrepared(clearDocument(), present: params.present, dryRun: request.dryRun)
        case IPCMethod.mirrorStatus:
            let params = try request.params.decode(MirrorTargetParams.self)
            return try await mirror.status(target: params.target).jsonValue()
        case IPCMethod.mirrorConnect:
            let params = try request.params.decode(MirrorConnectParams.self)
            return try await mirror.connect(target: params.target, mode: params.mode, dryRun: request.dryRun).jsonValue()
        case IPCMethod.mirrorDisconnect:
            let params = try request.params.decode(MirrorTargetParams.self)
            return try await mirror.disconnect(target: params.target, dryRun: request.dryRun).jsonValue()
        case IPCMethod.inputClick:
            let params = try request.params.decode(InputClickParams.self)
            let point = try await input.click(
                at: Point(x: params.x, y: params.y),
                button: params.button,
                clicks: params.clicks,
                dryRun: request.dryRun
            )
            return try point.jsonValue()
        case IPCMethod.inputMove:
            let params = try request.params.decode(InputMoveParams.self)
            return try await input.move(to: Point(x: params.x, y: params.y), dryRun: request.dryRun).jsonValue()
        case IPCMethod.inputScroll:
            let params = try request.params.decode(InputScrollParams.self)
            return try await input.scroll(
                at: Point(x: params.x, y: params.y),
                delta: params.delta,
                axis: params.axis,
                dryRun: request.dryRun
            ).jsonValue()
        case IPCMethod.inputPark:
            let params = try request.params.decode(InputParkParams.self)
            return try await input.park(
                displays: displays,
                display: params.display,
                corner: params.corner,
                inset: params.inset,
                dryRun: request.dryRun
            ).jsonValue()
        case IPCMethod.captureScreenshot:
            let params = try request.params.decode(ScreenshotParams.self)
            return try await capture.capture(display: params.display, displays: displays, to: params.path, dryRun: request.dryRun).jsonValue()
        case IPCMethod.displaysList:
            return try displays.jsonValue()
        case IPCMethod.systemPing:
            return try PingResult(running: true).jsonValue()
        case IPCMethod.systemShutdown:
            stop.stop()
            return try PingResult(running: false).jsonValue()
        default:
            throw HomeSignalError.usage("Unknown method \(request.method).")
        }
    }

    private func showPrepared(_ document: DisplayDocument, present: Bool, dryRun: Bool) async throws -> JSONValue {
        let prepared = try DisplayRendering.prepare(document)
        if dryRun {
            return try DisplayShowResult(
                contentHash: prepared.readback.contentHash,
                title: prepared.readback.title,
                kind: document.kind,
                verified: false
            ).jsonValue()
        }
        let actual = try await display.show(html: prepared.html, kind: document.kind, present: present)
        guard actual == prepared.readback else {
            throw HomeSignalError.displayMismatch(expected: prepared.readback, actual: actual)
        }
        if present && config.display.parkMouse {
            do {
                _ = try await input.park(
                    displays: displays,
                    display: config.input.parkDisplay,
                    corner: config.input.parkCorner,
                    inset: config.input.parkInset,
                    dryRun: false
                )
            } catch {
                log.error("Could not park the pointer: \(error)")
            }
        }
        return try DisplayShowResult(
            contentHash: actual.contentHash,
            title: actual.title,
            kind: actual.kind,
            verified: true
        ).jsonValue()
    }

    private func clearDocument() -> DisplayDocument {
        DisplayDocument(
            kind: DisplayKind.clear,
            background: config.display.background,
            foreground: config.display.foreground,
            accent: config.display.accent,
            messageSize: config.display.messageSize,
            titleSize: config.display.titleSize,
            rowSize: config.display.rowSize
        )
    }
}

public enum AgentServer {
    public static func serve(runtime: AgentRuntime, stop: StopFlag, path: String) async throws {
        Log(category: "agent").info("listening on \(path)")
        try await UnixSocket.serve(path: path, stop: stop) { data in
            await runtime.handleData(data)
        }
    }
}
