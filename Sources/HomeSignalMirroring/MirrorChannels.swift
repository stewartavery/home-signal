import HomeSignalCore

public actor SimulatedMirror: MirrorChannel {
    private var routes: [String: String] = [:]
    public init() {}

    public func status(target: String) async -> MirrorStatus {
        let mode = routes[target]
        return MirrorStatus(target: target, connected: mode != nil, mode: mode, changed: false)
    }

    public func connect(target: String, mode: String, deviceID: String, dryRun: Bool) async throws -> MirrorStatus {
        _ = deviceID
        let mode = try MirrorMode.validate(mode)
        if routes[target] != nil {
            return MirrorStatus(target: target, connected: true, mode: routes[target], changed: false)
        }
        if !dryRun {
            routes[target] = mode
        }
        return MirrorStatus(target: target, connected: true, mode: mode, changed: true)
    }

    public func disconnect(target: String, dryRun: Bool) async -> MirrorStatus {
        let existed = routes[target] != nil
        if !dryRun {
            routes[target] = nil
        }
        return MirrorStatus(target: target, connected: false, mode: nil, changed: existed)
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

    public func status(target: String) async throws -> MirrorStatus {
        let output = try await osascript(MirrorScript.controlCenter(target: target, deviceID: config.deviceID, action: "status", leaveOpen: false))
        let connected = output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        return MirrorStatus(target: target, connected: connected, mode: connected ? config.mode : nil, changed: false)
    }

    public func connect(target: String, mode: String, deviceID: String, dryRun: Bool) async throws -> MirrorStatus {
        let mode = try MirrorMode.validate(mode)
        let current = try await status(target: target)
        if current.connected {
            return MirrorStatus(target: target, connected: true, mode: current.mode ?? mode, changed: false)
        }
        if dryRun {
            return MirrorStatus(target: target, connected: true, mode: mode, changed: true)
        }
        let leaveOpen = mode == MirrorMode.window
        let id = deviceID.isEmpty ? config.deviceID : deviceID
        let output = try await osascript(MirrorScript.controlCenter(target: target, deviceID: id, action: "connect", leaveOpen: leaveOpen))
        var points: [Point] = []
        if leaveOpen {
            points = try await clickWindowRoute()
            _ = try await osascript(MirrorScript.closePanel())
        }
        if config.settleSeconds > 0 {
            try await sleeper.sleep(milliseconds: Int(config.settleSeconds * 1000))
        }
        let changed = !output.contains("already-connected")
        return MirrorStatus(target: target, connected: true, mode: mode, changed: changed, points: points.isEmpty ? nil : points)
    }

    public func disconnect(target: String, dryRun: Bool) async throws -> MirrorStatus {
        let current = try await status(target: target)
        if !current.connected {
            return MirrorStatus(target: target, connected: false, changed: false)
        }
        if dryRun {
            return MirrorStatus(target: target, connected: false, changed: true)
        }
        _ = try await osascript(MirrorScript.controlCenter(target: target, deviceID: config.deviceID, action: "disconnect", leaveOpen: false))
        return MirrorStatus(target: target, connected: false, changed: true)
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

    private func osascript(_ source: String) async throws -> String {
        let output = try await runner.execute(
            launchPath: "/usr/bin/osascript",
            arguments: ["-e", source],
            input: nil,
            timeoutSeconds: 30
        )
        guard output.status == 0 else {
            let detail = output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.contains("not found") {
                throw HomeSignalError.notFound("AirPlay target", name: config.target)
            }
            throw HomeSignalError.backend(
                detail.isEmpty ? "Control Center automation failed." : detail,
                hint: "Grant Accessibility and Automation permission to the agent."
            )
        }
        return output.stdoutText
    }
}

public struct FallbackMirror: MirrorChannel {
    private let primary: any MirrorChannel
    private let fallback: any MirrorChannel

    public init(primary: any MirrorChannel, fallback: any MirrorChannel) {
        self.primary = primary
        self.fallback = fallback
    }

    public func status(target: String) async throws -> MirrorStatus {
        try await recover { try await primary.status(target: target) } fallback: { try await fallback.status(target: target) }
    }

    public func connect(target: String, mode: String, deviceID: String, dryRun: Bool) async throws -> MirrorStatus {
        try await recover { try await primary.connect(target: target, mode: mode, deviceID: deviceID, dryRun: dryRun) } fallback: {
            try await fallback.connect(target: target, mode: mode, deviceID: deviceID, dryRun: dryRun)
        }
    }

    public func disconnect(target: String, dryRun: Bool) async throws -> MirrorStatus {
        try await recover { try await primary.disconnect(target: target, dryRun: dryRun) } fallback: {
            try await fallback.disconnect(target: target, dryRun: dryRun)
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

    public func status(target: String) async throws -> MirrorStatus {
        throw HomeSignalError.nativeRouteUnavailable
    }

    public func connect(target: String, mode: String, deviceID: String, dryRun: Bool) async throws -> MirrorStatus {
        _ = (target, mode, deviceID, dryRun)
        throw HomeSignalError.nativeRouteUnavailable
    }

    public func disconnect(target: String, dryRun: Bool) async throws -> MirrorStatus {
        _ = (target, dryRun)
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
