import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol LightBackend: Sendable {
    var backendID: String { get }
    func listDevices() async throws -> [LightDevice]
    func getLight(_ name: String) async throws -> LightState
    func setLight(_ name: String, _ patch: LightPatch) async throws -> LightState
    func listScenes() async throws -> [Scene]
    func runScene(_ name: String) async throws
}

public protocol DisplayChannel: Sendable {
    func show(html: String, kind: String, present: Bool) async throws -> DisplayReadback
    func readback() async -> DisplayReadback?
    func clear(present: Bool) async throws
}

public protocol DisplayPowerControlling: Sendable {
    func wakeAndHold(reason: String) async throws
    func release() async
    func isHolding() async -> Bool
}

public protocol AttachedDisplayListing: Sendable {
    func attachedDisplays() async -> [AttachedDisplay]
}

public protocol DisplayPlacing: Sendable {
    func place(html: String, kind: String, present: Bool, target: DisplayTarget) async throws -> PlacementReport
    func dismiss() async
}

public protocol AirPlayDiscovering: Sendable {
    func discover(timeoutSeconds: Double) async -> [String]
}

public struct EmptyAirPlayBrowser: AirPlayDiscovering {
    public init() {}

    public func discover(timeoutSeconds: Double) async -> [String] {
        _ = timeoutSeconds
        return []
    }
}

public protocol MirrorChannel: Sendable {
    func status(target: String, debugAX: Bool, debugFile: String?) async throws -> MirrorStatus
    func connect(target: String, mode: String, deviceID: String, dryRun: Bool, debugAX: Bool, debugFile: String?) async throws -> MirrorStatus
    func disconnect(target: String, dryRun: Bool, debugAX: Bool, debugFile: String?) async throws -> MirrorStatus
    func list(discover: Bool, debugAX: Bool, debugFile: String?) async throws -> MirrorListResult
}

public protocol MirrorBackendSelecting: MirrorChannel {
    func status(backend: String, target: String, debugAX: Bool, debugFile: String?, routingDebug: Bool) async throws -> MirrorStatus
    func connect(backend: String, target: String, mode: String, deviceID: String, dryRun: Bool, debugAX: Bool, debugFile: String?, routingDebug: Bool) async throws -> MirrorStatus
    func disconnect(backend: String, target: String, dryRun: Bool, debugAX: Bool, debugFile: String?, routingDebug: Bool) async throws -> MirrorStatus
    func list(backend: String, discover: Bool, debugAX: Bool, debugFile: String?, routingDebug: Bool) async throws -> MirrorListResult
}

public protocol InputChannel: Sendable {
    func click(at point: Point, button: String, clicks: Int, dryRun: Bool) async throws -> Point
    func move(to point: Point, dryRun: Bool) async throws -> Point
    func scroll(at point: Point, delta: Int, axis: String, dryRun: Bool) async throws -> Point
    func park(displays: [DisplayBounds], display: String, corner: String, inset: Int, dryRun: Bool) async throws -> Point
}

public protocol CaptureChannel: Sendable {
    func capture(display: String, displays: [DisplayBounds], to path: String?, dryRun: Bool) async throws -> CaptureResult
}

public protocol Sleeper: Sendable {
    func sleep(milliseconds: Int) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}

    public func sleep(milliseconds: Int) async throws {
        guard milliseconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }
}

public struct ImmediateSleeper: Sleeper {
    public init() {}

    public func sleep(milliseconds: Int) async throws {}
}

public struct CommandOutput: Sendable, Equatable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data

    public init(status: Int32, stdout: Data, stderr: Data) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutText: String {
        String(decoding: stdout, as: UTF8.self)
    }

    public var stderrText: String {
        String(decoding: stderr, as: UTF8.self)
    }
}

public protocol CommandRunning: Sendable {
    func execute(launchPath: String, arguments: [String], input: Data?, timeoutSeconds: Double) async throws -> CommandOutput
}

public struct HTTPResult: Sendable, Equatable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol HTTPSending: Sendable {
    func send(url: URL, method: String, body: Data?, bearer: String?) async throws -> HTTPResult
}

public struct URLSessionHTTP: HTTPSending {
    public init() {}

    public func send(url: URL, method: String, body: Data?, bearer: String?) async throws -> HTTPResult {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer, !bearer.isEmpty {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return HTTPResult(status: status, body: data)
    }
}
