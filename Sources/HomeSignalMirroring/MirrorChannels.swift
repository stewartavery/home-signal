import HomeSignalCore

public actor SimulatedMirror: MirrorChannel {
    private var routes: [String: String] = [:]
    public init() {}

    public func status(target: String, debugAX: Bool) async -> MirrorStatus {
        _ = debugAX
        let mode = routes[target]
        return MirrorStatus(target: target, connected: mode != nil, mode: mode, changed: false)
    }

    public func connect(target: String, mode: String, deviceID: String, dryRun: Bool, debugAX: Bool) async throws -> MirrorStatus {
        _ = (deviceID, debugAX)
        let mode = try MirrorMode.validate(mode)
        if routes[target] != nil {
            return MirrorStatus(target: target, connected: true, mode: routes[target], changed: false)
        }
        if !dryRun {
            routes[target] = mode
        }
        return MirrorStatus(target: target, connected: true, mode: mode, changed: true)
    }

    public func disconnect(target: String, dryRun: Bool, debugAX: Bool) async -> MirrorStatus {
        _ = debugAX
        let existed = routes[target] != nil
        if !dryRun {
            routes[target] = nil
        }
        return MirrorStatus(target: target, connected: false, mode: nil, changed: existed)
    }

    public func list(discover: Bool, debugAX: Bool) async -> MirrorListResult {
        let names = routes.keys.sorted()
        return MirrorListResult(
            controlCenter: names,
            discovered: discover ? names : [],
            routes: names.map { MirrorRoute(name: $0, identifier: "", selected: true) },
            accessibility: debugAX ? [MirrorAXStep(step: "simulated", tree: "")] : []
        )
    }
}

public struct SystemEventsMirror: MirrorChannel {
    public typealias Clicker = @Sendable (Point) async throws -> Void

    private let config: MirrorConfig
    private let displays: @Sendable () -> [DisplayBounds]
    private let runner: any CommandRunning
    private let clicker: Clicker
    private let sleeper: any Sleeper

    public init(
        config: MirrorConfig,
        displays: @escaping @Sendable () -> [DisplayBounds],
        runner: any CommandRunning = ProcessCommandRunner(),
        clicker: @escaping Clicker,
        sleeper: any Sleeper = TaskSleeper()
    ) {
        self.config = config
        self.displays = displays
        self.runner = runner
        self.clicker = clicker
        self.sleeper = sleeper
    }

    public func status(target: String, debugAX: Bool) async throws -> MirrorStatus {
        let found = try await resolve(target: target, deviceID: config.deviceID, debugAX: debugAX, leaveOpen: false)
        return MirrorStatus(target: target, connected: found.selected, mode: found.selected ? config.mode : nil, changed: false)
    }

    public func connect(target: String, mode: String, deviceID: String, dryRun: Bool, debugAX: Bool) async throws -> MirrorStatus {
        let mode = try MirrorMode.validate(mode)
        let id = deviceID.isEmpty ? config.deviceID : deviceID
        let opened = try await openRoutes(debugAX: debugAX, leaveOpen: true)
        do {
            guard let found = MirrorAX.find(target: target, deviceID: id, in: opened.routes) else {
                try await closePanel()
                throw HomeSignalError.airPlayNotFound(
                    target: target,
                    seen: opened.routes.map(\.name),
                    debug: debugAX ? MirrorAXDebug.text(opened.steps) : nil
                )
            }
            if found.selected || dryRun {
                try await closePanel()
                return MirrorStatus(target: target, connected: true, mode: mode, changed: !found.selected)
            }
            var steps = opened.steps
            _ = try await run(MirrorScript.clickRoute(found.name), steps: &steps, step: "click-route", debugAX: debugAX)
            var points: [Point] = []
            if mode == MirrorMode.window {
                points = try await clickWindowRoute()
            }
            try await closePanel()
            if config.settleSeconds > 0 {
                try await sleeper.sleep(milliseconds: Int(config.settleSeconds * 1000))
            }
            return MirrorStatus(target: target, connected: true, mode: mode, changed: true, points: points.isEmpty ? nil : points)
        } catch {
            try await closePanel()
            throw error
        }
    }

    public func disconnect(target: String, dryRun: Bool, debugAX: Bool) async throws -> MirrorStatus {
        let opened = try await openRoutes(debugAX: debugAX, leaveOpen: true)
        do {
            guard let found = MirrorAX.find(target: target, deviceID: config.deviceID, in: opened.routes) else {
                try await closePanel()
                throw HomeSignalError.airPlayNotFound(
                    target: target,
                    seen: opened.routes.map(\.name),
                    debug: debugAX ? MirrorAXDebug.text(opened.steps) : nil
                )
            }
            if !found.selected || dryRun {
                try await closePanel()
                return MirrorStatus(target: target, connected: false, changed: found.selected && dryRun)
            }
            var steps = opened.steps
            _ = try await run(MirrorScript.clickRoute(found.name), steps: &steps, step: "click-route", debugAX: debugAX)
            try await closePanel()
            return MirrorStatus(target: target, connected: false, changed: true)
        } catch {
            try await closePanel()
            throw error
        }
    }

    public func list(discover: Bool, debugAX: Bool) async throws -> MirrorListResult {
        _ = discover
        let opened = try await openRoutes(debugAX: debugAX, leaveOpen: false)
        return MirrorListResult(
            controlCenter: opened.routes.map(\.name),
            discovered: [],
            routes: opened.routes,
            accessibility: debugAX ? opened.steps : []
        )
    }

    private func clickWindowRoute() async throws -> [Point] {
        let raw = try await osascript(MirrorScript.panelBounds())
        let parts = raw.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? .nan }
        let panel: PanelBounds?
        if parts.count == 4, parts.allSatisfy({ $0.isFinite }) {
            panel = PanelBounds(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        } else {
            panel = nil
        }
        let screens = displays()
        let specs: [ClickSpec]
        if panel == nil, config.absolute.isComplete {
            specs = [
                .absolute(config.absolute.chooseContent!),
                .absolute(config.absolute.windowOrApp!),
                .absolute(config.absolute.mirrorThisWindow!),
            ]
        } else {
            specs = [
                .panelFraction(x: config.clicks.chooseContent.x, y: config.clicks.chooseContent.y),
                .panelFraction(x: config.clicks.windowOrApp.x, y: config.clicks.windowOrApp.y),
                .panelFraction(x: config.clicks.mirrorThisWindow.x, y: config.clicks.mirrorThisWindow.y),
            ]
        }
        var points: [Point] = []
        for spec in specs {
            let point = try DisplayGeometry.resolve(spec, panel: panel, displays: screens)
            points.append(point)
            try await clicker(point)
            try await sleeper.sleep(milliseconds: 350)
        }
        return points
    }

    private func resolve(target: String, deviceID: String, debugAX: Bool, leaveOpen: Bool) async throws -> MirrorRoute {
        let opened = try await openRoutes(debugAX: debugAX, leaveOpen: leaveOpen)
        if let match = MirrorAX.find(target: target, deviceID: deviceID, in: opened.routes) {
            return match
        }
        throw HomeSignalError.airPlayNotFound(
            target: target,
            seen: opened.routes.map(\.name),
            debug: debugAX ? MirrorAXDebug.text(opened.steps) : nil
        )
    }

    private func openRoutes(debugAX: Bool, leaveOpen: Bool) async throws -> (routes: [MirrorRoute], steps: [MirrorAXStep]) {
        var steps: [MirrorAXStep] = []
        do {
            let menuText = try await run(MirrorScript.dumpMenuBar(), steps: &steps, step: "menubar", debugAX: debugAX)
            let menu = MirrorAX.parse(menuText)
            switch MirrorAX.menuBarChoice(menu) {
            case .screenMirroring(let label):
                _ = try await run(MirrorScript.clickMenuBar(label), steps: &steps, step: "click-screen-mirroring", debugAX: debugAX)
            case .controlCenter(let label):
                _ = try await run(MirrorScript.clickMenuBar(label), steps: &steps, step: "click-control-center", debugAX: debugAX)
                let windowText = try await run(MirrorScript.dumpWindow(), steps: &steps, step: "window", debugAX: debugAX)
                let window = MirrorAX.parse(windowText)
                guard let module = MirrorAX.screenMirroringModule(window) else {
                    if !leaveOpen {
                        _ = try? await run(MirrorScript.closePanel(), steps: &steps, step: "close", debugAX: false)
                    }
                    throw HomeSignalError.screenMirroringUnavailable(
                        seen: MirrorAX.labels(window),
                        debug: debugAX ? MirrorAXDebug.text(steps) : nil
                    )
                }
                let moduleLabel = module.description.isEmpty ? module.title : module.description
                _ = try await run(
                    MirrorScript.clickModule(identifier: module.identifier, description: moduleLabel),
                    steps: &steps,
                    step: "click-module",
                    debugAX: debugAX
                )
            case .notFound:
                throw HomeSignalError.screenMirroringUnavailable(
                    seen: MirrorAX.labels(menu),
                    debug: debugAX ? MirrorAXDebug.text(steps) : nil
                )
            }
            let routes = try await pollRoutes(&steps, debugAX: debugAX)
            if !leaveOpen {
                _ = try? await run(MirrorScript.closePanel(), steps: &steps, step: "close", debugAX: false)
            }
            return (routes, steps)
        } catch {
            if !leaveOpen {
                _ = try? await run(MirrorScript.closePanel(), steps: &steps, step: "close", debugAX: false)
            }
            throw error
        }
    }

    private func pollRoutes(_ steps: inout [MirrorAXStep], debugAX: Bool) async throws -> [MirrorRoute] {
        let timeoutMs = 8000
        let poll = 400
        var waited = 0
        var last: [MirrorRoute] = []
        while true {
            let text = try await run(MirrorScript.dumpRoutes(), steps: &steps, step: "routes", debugAX: debugAX)
            last = MirrorAX.routes(MirrorAX.parse(text))
            if !last.isEmpty || waited >= timeoutMs {
                return last
            }
            let step = min(poll, timeoutMs - waited)
            try await sleeper.sleep(milliseconds: step)
            waited += step
        }
    }

    private func run(_ source: String, steps: inout [MirrorAXStep], step: String, debugAX: Bool) async throws -> String {
        let output = try await osascript(source)
        if debugAX || step == "menubar" || step == "window" || step == "routes" {
            let records = MirrorAX.parse(output)
            let tree = records.isEmpty ? output : MirrorAX.format(records)
            steps.append(MirrorAXStep(step: step, tree: tree))
        }
        return output
    }

    private func closePanel() async throws {
        _ = try? await osascript(MirrorScript.closePanel())
    }

    private func osascript(_ source: String) async throws -> String {
        let output = try await runner.execute(
            launchPath: "/usr/bin/osascript",
            arguments: ["-e", source],
            input: nil,
            timeoutSeconds: 30
        )
        let detail = (output.stderrText + "\n" + output.stdoutText).trimmingCharacters(in: .whitespacesAndNewlines)
        if MirrorAX.permissionProblem(detail) {
            throw HomeSignalError.permissionDenied(detail)
        }
        guard output.status == 0 else {
            throw HomeSignalError.backend(
                detail.isEmpty ? "Control Center automation failed." : detail,
                hint: "Grant Accessibility and Automation permission to the agent. Pass --debug-ax to dump the accessibility tree."
            )
        }
        return output.stdoutText
    }
}

enum MirrorAXDebug {
    static func text(_ steps: [MirrorAXStep]) -> String {
        steps.map { "[\($0.step)]\n\($0.tree)" }.joined(separator: "\n")
    }
}

public struct FallbackMirror: MirrorChannel {
    private let primary: any MirrorChannel
    private let fallback: any MirrorChannel

    public init(primary: any MirrorChannel, fallback: any MirrorChannel) {
        self.primary = primary
        self.fallback = fallback
    }

    public func status(target: String, debugAX: Bool) async throws -> MirrorStatus {
        try await recover { try await primary.status(target: target, debugAX: debugAX) } fallback: {
            try await fallback.status(target: target, debugAX: debugAX)
        }
    }

    public func connect(target: String, mode: String, deviceID: String, dryRun: Bool, debugAX: Bool) async throws -> MirrorStatus {
        try await recover {
            try await primary.connect(target: target, mode: mode, deviceID: deviceID, dryRun: dryRun, debugAX: debugAX)
        } fallback: {
            try await fallback.connect(target: target, mode: mode, deviceID: deviceID, dryRun: dryRun, debugAX: debugAX)
        }
    }

    public func disconnect(target: String, dryRun: Bool, debugAX: Bool) async throws -> MirrorStatus {
        try await recover { try await primary.disconnect(target: target, dryRun: dryRun, debugAX: debugAX) } fallback: {
            try await fallback.disconnect(target: target, dryRun: dryRun, debugAX: debugAX)
        }
    }

    public func list(discover: Bool, debugAX: Bool) async throws -> MirrorListResult {
        try await recover { try await primary.list(discover: discover, debugAX: debugAX) } fallback: {
            try await fallback.list(discover: discover, debugAX: debugAX)
        }
    }

    private func recover<T>(_ body: () async throws -> T, fallback fallbackBody: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as HomeSignalError where error.code == "native_route_unavailable" {
            return try await fallbackBody()
        }
    }
}

public struct UnavailableNativeMirror: MirrorChannel {
    public init() {}

    public func status(target: String, debugAX: Bool) async throws -> MirrorStatus {
        _ = (target, debugAX)
        throw HomeSignalError.nativeRouteUnavailable
    }

    public func connect(target: String, mode: String, deviceID: String, dryRun: Bool, debugAX: Bool) async throws -> MirrorStatus {
        _ = (target, mode, deviceID, dryRun, debugAX)
        throw HomeSignalError.nativeRouteUnavailable
    }

    public func disconnect(target: String, dryRun: Bool, debugAX: Bool) async throws -> MirrorStatus {
        _ = (target, dryRun, debugAX)
        throw HomeSignalError.nativeRouteUnavailable
    }

    public func list(discover: Bool, debugAX: Bool) async throws -> MirrorListResult {
        _ = (discover, debugAX)
        throw HomeSignalError.nativeRouteUnavailable
    }
}

#if os(macOS)
import AppKit

public enum MacDisplayProbe {
    public static func read() -> [DisplayBounds] {
        let screens = NSScreen.screens
        let frames = screens.map { screen in
            CocoaFrame(x: screen.frame.origin.x, y: screen.frame.origin.y, width: screen.frame.width, height: screen.frame.height)
        }
        return zip(screens, DisplayGeometry.fromCocoaFrames(frames)).map { screen, bounds in
            DisplayBounds(
                name: screen.localizedName,
                width: bounds.width,
                height: bounds.height,
                originX: bounds.originX,
                originY: bounds.originY,
                primary: bounds.primary,
                deviceID: screenNumber(screen)
            )
        }
    }

    private static func screenNumber(_ screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return "" }
        return number.stringValue
    }
}
#endif
