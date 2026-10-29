import Foundation
import HomeSignalCore

public struct MediaRoutingMirror: MirrorChannel {
    private let probe: any MediaRouteProbing

    public init(probe: any MediaRouteProbing) {
        self.probe = probe
    }

    public func status(target: String, debugAX: Bool, debugFile: String?) async throws -> MirrorStatus {
        _ = (debugAX, debugFile)
        return try await status(target: target, routingDebug: false)
    }

    public func connect(target: String, mode: String, deviceID: String, dryRun: Bool, debugAX: Bool, debugFile: String?) async throws -> MirrorStatus {
        _ = (mode, debugAX, debugFile)
        return try await connect(target: target, deviceID: deviceID, dryRun: dryRun, routingDebug: false)
    }

    public func disconnect(target: String, dryRun: Bool, debugAX: Bool, debugFile: String?) async throws -> MirrorStatus {
        _ = (debugAX, debugFile)
        return try await disconnect(target: target, dryRun: dryRun, routingDebug: false)
    }

    public func list(discover: Bool, debugAX: Bool, debugFile: String?) async throws -> MirrorListResult {
        _ = (discover, debugAX, debugFile)
        return try await listed(routingDebug: false)
    }

    func status(target: String, routingDebug: Bool) async throws -> MirrorStatus {
        let snapshot = await probe.snapshot()
        try Self.ensureLoaded(snapshot)
        let devices = RouteSelection.choose(snapshot)
        guard let found = RouteSelection.match(target: target, deviceID: "", in: devices) else {
            throw Self.miss(target: target, devices: devices, snapshot: snapshot, routingDebug: routingDebug)
        }
        return MirrorStatus(target: target, connected: found.selected, mode: found.selected ? "routing" : nil, changed: false, note: routingDebug ? RouteSelection.debugText(snapshot) : nil)
    }

    func connect(target: String, deviceID: String, dryRun: Bool, routingDebug: Bool) async throws -> MirrorStatus {
        let snapshot = await probe.snapshot()
        try Self.ensureLoaded(snapshot)
        let devices = RouteSelection.choose(snapshot)
        guard let found = RouteSelection.match(target: target, deviceID: deviceID, in: devices) else {
            throw Self.miss(target: target, devices: devices, snapshot: snapshot, routingDebug: routingDebug)
        }
        let debug = RouteSelection.debugText(snapshot)
        guard snapshot.screenContext else {
            throw HomeSignalError.screenMirrorUnavailable(debug)
        }
        if found.selected || dryRun {
            return MirrorStatus(target: target, connected: true, mode: "display", changed: !found.selected, note: routingDebug ? debug : nil)
        }
        let after = try await probe.setScreenRoute(identifier: found.identifier.isEmpty ? found.name : found.identifier, enabled: true, dryRun: false)
        guard after.screenContext else {
            throw HomeSignalError.screenMirrorUnavailable(RouteSelection.debugText(after))
        }
        return MirrorStatus(target: target, connected: true, mode: "display", changed: true, note: routingDebug ? RouteSelection.debugText(after) : nil)
    }

    func disconnect(target: String, dryRun: Bool, routingDebug: Bool) async throws -> MirrorStatus {
        let snapshot = await probe.snapshot()
        try Self.ensureLoaded(snapshot)
        let devices = RouteSelection.choose(snapshot)
        guard let found = RouteSelection.match(target: target, deviceID: "", in: devices) else {
            throw Self.miss(target: target, devices: devices, snapshot: snapshot, routingDebug: routingDebug)
        }
        guard snapshot.screenContext else {
            throw HomeSignalError.screenMirrorUnavailable(RouteSelection.debugText(snapshot))
        }
        if !found.selected || dryRun {
            return MirrorStatus(target: target, connected: false, changed: found.selected && dryRun, note: routingDebug ? RouteSelection.debugText(snapshot) : nil)
        }
        _ = try await probe.setScreenRoute(identifier: found.identifier.isEmpty ? found.name : found.identifier, enabled: false, dryRun: false)
        return MirrorStatus(target: target, connected: false, changed: true, note: routingDebug ? RouteSelection.debugText(snapshot) : nil)
    }

    func listed(routingDebug: Bool) async throws -> MirrorListResult {
        let snapshot = await probe.snapshot()
        try Self.ensureLoaded(snapshot)
        let devices = RouteSelection.choose(snapshot)
        let debug = RouteSelection.debugText(snapshot)
        return MirrorListResult(
            controlCenter: devices.map(\.name),
            discovered: [],
            routes: RouteSelection.routes(from: devices),
            accessibility: routingDebug ? [MirrorAXStep(step: "routing", tree: debug)] : [],
            source: "routing",
            routingDebug: routingDebug ? debug : nil
        )
    }

    private static func ensureLoaded(_ snapshot: RouteSnapshot) throws {
        if snapshot.loaded { return }
        throw HomeSignalError.routingUnavailable(snapshot.note.isEmpty ? "No media routing classes were found." : snapshot.note)
    }

    private static func miss(target: String, devices: [RouteCandidate], snapshot: RouteSnapshot, routingDebug: Bool) -> HomeSignalError {
        let debug = routingDebug ? RouteSelection.debugText(snapshot) : snapshot.note
        if snapshot.screenContext {
            return HomeSignalError.airPlayNotFound(target: target, seen: devices.map(\.name), debug: debug)
        }
        return HomeSignalError.routingUnavailable("\(target) is not in the media route list. \(debug)")
    }
}

public struct AdaptiveMirror: MirrorChannel, MirrorBackendSelecting {
    private let routing: MediaRoutingMirror
    private let interface: any MirrorChannel
    private let locks: any SessionLockReading

    public init(routing: MediaRoutingMirror, interface: any MirrorChannel, locks: any SessionLockReading) {
        self.routing = routing
        self.interface = interface
        self.locks = locks
    }

    public func status(target: String, debugAX: Bool, debugFile: String?) async throws -> MirrorStatus {
        return try await status(backend: "auto", target: target, debugAX: debugAX, debugFile: debugFile, routingDebug: false)
    }

    public func connect(target: String, mode: String, deviceID: String, dryRun: Bool, debugAX: Bool, debugFile: String?) async throws -> MirrorStatus {
        return try await connect(backend: "auto", target: target, mode: mode, deviceID: deviceID, dryRun: dryRun, debugAX: debugAX, debugFile: debugFile, routingDebug: false)
    }

    public func disconnect(target: String, dryRun: Bool, debugAX: Bool, debugFile: String?) async throws -> MirrorStatus {
        return try await disconnect(backend: "auto", target: target, dryRun: dryRun, debugAX: debugAX, debugFile: debugFile, routingDebug: false)
    }

    public func list(discover: Bool, debugAX: Bool, debugFile: String?) async throws -> MirrorListResult {
        return try await list(backend: "auto", discover: discover, debugAX: debugAX, debugFile: debugFile, routingDebug: false)
    }

    public func status(backend: String, target: String, debugAX: Bool, debugFile: String?, routingDebug: Bool) async throws -> MirrorStatus {
        switch try MirrorBackendChoice.parse(backend) {
        case .routing:
            return try await routing.status(target: target, routingDebug: routingDebug)
        case .controlcenter:
            try ensureInterface()
            return try await interface.status(target: target, debugAX: debugAX, debugFile: debugFile)
        case .auto:
            do {
                return try await routing.status(target: target, routingDebug: routingDebug)
            } catch let error as HomeSignalError where Self.canFallBack(error) {
                try ensureInterface(detail: error.message)
                return try await interface.status(target: target, debugAX: debugAX, debugFile: debugFile)
            }
        }
    }

    public func connect(backend: String, target: String, mode: String, deviceID: String, dryRun: Bool, debugAX: Bool, debugFile: String?, routingDebug: Bool) async throws -> MirrorStatus {
        switch try MirrorBackendChoice.parse(backend) {
        case .routing:
            return try await routing.connect(target: target, deviceID: deviceID, dryRun: dryRun, routingDebug: routingDebug)
        case .controlcenter:
            try ensureInterface()
            return try await interface.connect(target: target, mode: mode, deviceID: deviceID, dryRun: dryRun, debugAX: debugAX, debugFile: debugFile)
        case .auto:
            do {
                return try await routing.connect(target: target, deviceID: deviceID, dryRun: dryRun, routingDebug: routingDebug)
            } catch let error as HomeSignalError where Self.canFallBack(error) {
                try ensureInterface(detail: error.message)
                return try await interface.connect(target: target, mode: mode, deviceID: deviceID, dryRun: dryRun, debugAX: debugAX, debugFile: debugFile)
            }
        }
    }

    public func disconnect(backend: String, target: String, dryRun: Bool, debugAX: Bool, debugFile: String?, routingDebug: Bool) async throws -> MirrorStatus {
        switch try MirrorBackendChoice.parse(backend) {
        case .routing:
            return try await routing.disconnect(target: target, dryRun: dryRun, routingDebug: routingDebug)
        case .controlcenter:
            try ensureInterface()
            return try await interface.disconnect(target: target, dryRun: dryRun, debugAX: debugAX, debugFile: debugFile)
        case .auto:
            do {
                return try await routing.disconnect(target: target, dryRun: dryRun, routingDebug: routingDebug)
            } catch let error as HomeSignalError where Self.canFallBack(error) {
                try ensureInterface(detail: error.message)
                return try await interface.disconnect(target: target, dryRun: dryRun, debugAX: debugAX, debugFile: debugFile)
            }
        }
    }

    public func list(backend: String, discover: Bool, debugAX: Bool, debugFile: String?, routingDebug: Bool) async throws -> MirrorListResult {
        _ = discover
        switch try MirrorBackendChoice.parse(backend) {
        case .routing:
            return try await routing.listed(routingDebug: routingDebug)
        case .controlcenter:
            try ensureInterface()
            return try await interface.list(discover: false, debugAX: debugAX, debugFile: debugFile)
        case .auto:
            do {
                let listed = try await routing.listed(routingDebug: routingDebug)
                if !listed.controlCenter.isEmpty || locks.isScreenLocked() {
                    return listed
                }
            } catch let error as HomeSignalError where error.code == "routing_unavailable" {
                try ensureInterface(detail: error.message)
                return try await interface.list(discover: false, debugAX: debugAX, debugFile: debugFile)
            }
            try ensureInterface()
            return try await interface.list(discover: false, debugAX: debugAX, debugFile: debugFile)
        }
    }

    private func ensureInterface(detail: String = "Control Center needs an unlocked screen.") throws {
        if locks.isScreenLocked() {
            throw HomeSignalError.screenLocked(detail: detail)
        }
    }

    private static func canFallBack(_ error: HomeSignalError) -> Bool {
        error.code == "routing_unavailable" || error.code == "screen_mirror_unavailable"
    }
}
