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
    private let power: any DisplayPowerControlling
    private let screens: any AttachedDisplayListing
    private let placer: any DisplayPlacing
    private let session: DisplaySession
    private let browser: any AirPlayDiscovering
    private var holdingWake = false
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
        stop: StopFlag = StopFlag(),
        power: (any DisplayPowerControlling)? = nil,
        screens: (any AttachedDisplayListing)? = nil,
        placer: (any DisplayPlacing)? = nil,
        browser: any AirPlayDiscovering = EmptyAirPlayBrowser()
    ) {
        let resolvedDisplays = displays ?? config.displays
        self.config = config
        self.displays = resolvedDisplays
        self.lights = lights
        self.display = display
        self.mirror = mirror
        self.input = input
        self.capture = capture
        self.blink = BlinkService(sleeper: sleeper)
        self.stop = stop
        let resolvedPower = power ?? SimulatedDisplayPower()
        let resolvedScreens = screens ?? StaticAttachedDisplays(AttachedDisplay.includingTarget(config, geometry: resolvedDisplays))
        let resolvedPlacer = placer ?? (display as? any DisplayPlacing) ?? ChannelDisplayPlacer(display)
        self.power = resolvedPower
        self.screens = resolvedScreens
        self.placer = resolvedPlacer
        self.session = DisplaySession(
            power: resolvedPower,
            screens: resolvedScreens,
            mirror: mirror,
            placer: resolvedPlacer,
            sleeper: sleeper,
            reconnectSeconds: config.display.reconnectSeconds,
            mirrorMode: config.mirror.mode
        )
        self.browser = browser
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
                channels: ["lights", "scenes", "display", "mirror", "input", "capture", "power"]
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
        case IPCMethod.homeBlink:
            let params = try request.params.decode(HomeBlinkParams.self)
            return try await blink.blinkAccessory(
                lights,
                accessory: params.accessory,
                times: params.times,
                intervalSeconds: params.intervalSeconds,
                color: params.color,
                dryRun: request.dryRun
            ).jsonValue()
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
            return try await showPrepared(
                params.document,
                present: params.present,
                dryRun: request.dryRun,
                targetName: params.targetName,
                targetDeviceID: params.targetDeviceID
            )
        case IPCMethod.displayStatus:
            return try await display.readback().jsonValue()
        case IPCMethod.displayClear:
            _ = try request.params.decode(PresentParams.self)
            return try await stopDisplay(dryRun: request.dryRun)
        case IPCMethod.mirrorStatus:
            let params = try request.params.decode(MirrorTargetParams.self)
            return try await mirror.status(target: params.target, debugAX: params.debugAX, debugFile: params.debugFile).jsonValue()
        case IPCMethod.mirrorConnect:
            let params = try request.params.decode(MirrorConnectParams.self)
            return try await mirror.connect(
                target: params.target,
                mode: params.mode,
                deviceID: params.deviceID,
                dryRun: request.dryRun,
                debugAX: params.debugAX,
                debugFile: params.debugFile
            ).jsonValue()
        case IPCMethod.mirrorDisconnect:
            let params = try request.params.decode(MirrorTargetParams.self)
            return try await mirror.disconnect(target: params.target, dryRun: request.dryRun, debugAX: params.debugAX, debugFile: params.debugFile).jsonValue()
        case IPCMethod.mirrorList:
            let params = try request.params.decode(MirrorListParams.self)
            var listed = try await mirror.list(discover: false, debugAX: params.debugAX, debugFile: params.debugFile)
            if params.discover {
                listed = listed.with(discovered: await browser.discover(timeoutSeconds: 3))
            }
            return try listed.jsonValue()
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
            await session.stop()
            holdingWake = false
            stop.stop()
            return try PingResult(running: false).jsonValue()
        default:
            throw HomeSignalError.usage("Unknown method \(request.method).")
        }
    }

    private func showPrepared(_ document: DisplayDocument, present: Bool, dryRun: Bool, targetName: String? = nil, targetDeviceID: String? = nil) async throws -> JSONValue {
        let prepared = try DisplayRendering.prepare(document)
        let target = try DisplayTarget.resolve(overrideName: targetName, overrideID: targetDeviceID, config: config)
        let attached = await screens.attachedDisplays()
        if dryRun {
            let match = DisplayMatch.find(target, in: attached)
            return try DisplayShowResult(
                contentHash: prepared.readback.contentHash,
                title: prepared.readback.title,
                kind: document.kind,
                verified: false,
                target: target.name,
                deviceID: target.deviceID,
                screen: match?.name ?? "",
                fullScreen: false,
                onTarget: match != nil,
                holdingWake: holdingWake,
                dryRun: true,
                attached: attached.map(\.name)
            ).jsonValue()
        }
        do {
            let result = try await session.show(
                html: prepared.html,
                readback: prepared.readback,
                present: present,
                target: target,
                alreadyHolding: holdingWake
            )
            holdingWake = result.holdingWake
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
            return try result.jsonValue()
        } catch {
            holdingWake = await power.isHolding()
            throw error
        }
    }

    private func stopDisplay(dryRun: Bool) async throws -> JSONValue {
        let target = try DisplayTarget.resolve(overrideName: nil, overrideID: nil, config: config)
        let attached = await screens.attachedDisplays()
        if dryRun {
            return try DisplayShowResult(
                contentHash: "",
                title: nil,
                kind: DisplayKind.clear,
                verified: false,
                target: target.name,
                deviceID: target.deviceID,
                screen: "",
                fullScreen: false,
                onTarget: false,
                holdingWake: holdingWake,
                dryRun: true,
                attached: attached.map(\.name)
            ).jsonValue()
        }
        await session.stop()
        holdingWake = false
        return try DisplayShowResult(
            contentHash: "",
            title: nil,
            kind: DisplayKind.clear,
            verified: false,
            target: target.name,
            deviceID: target.deviceID,
            screen: "",
            fullScreen: false,
            onTarget: false,
            holdingWake: false,
            dryRun: false,
            attached: attached.map(\.name)
        ).jsonValue()
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
