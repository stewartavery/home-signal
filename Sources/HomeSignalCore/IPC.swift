import Foundation

public enum IPCMethod {
    public static let capabilities = "capabilities"
    public static let lightsList = "lights.list"
    public static let lightsGet = "lights.get"
    public static let lightsSet = "lights.set"
    public static let lightsBlink = "lights.blink"
    public static let homeBlink = "home.blink"
    public static let scenesList = "scenes.list"
    public static let scenesRun = "scenes.run"
    public static let displayShow = "display.show"
    public static let displayStatus = "display.status"
    public static let displayClear = "display.clear"
    public static let mirrorStatus = "mirror.status"
    public static let mirrorConnect = "mirror.connect"
    public static let mirrorDisconnect = "mirror.disconnect"
    public static let inputClick = "input.click"
    public static let inputMove = "input.move"
    public static let inputScroll = "input.scroll"
    public static let inputPark = "input.park"
    public static let captureScreenshot = "capture.screenshot"
    public static let displaysList = "displays.list"
    public static let systemPing = "system.ping"
    public static let systemShutdown = "system.shutdown"

    public static let all = [
        capabilities, lightsList, lightsGet, lightsSet, lightsBlink, homeBlink, scenesList, scenesRun,
        displayShow, displayStatus, displayClear, mirrorStatus, mirrorConnect, mirrorDisconnect,
        inputClick, inputMove, inputScroll, inputPark, captureScreenshot, displaysList, systemPing, systemShutdown,
    ]
}

public struct IPCRequest: Sendable, Equatable, Codable {
    public var protocolVersion: Int
    public var id: String
    public var method: String
    public var params: JSONValue
    public var dryRun: Bool

    public init(id: String = UUID().uuidString, method: String, params: JSONValue = .object([:]), dryRun: Bool = false) {
        self.protocolVersion = HomeSignalVersion.protocolVersion
        self.id = id
        self.method = method
        self.params = params
        self.dryRun = dryRun
    }
}

public struct IPCErrorBody: Sendable, Equatable, Codable {
    public var code: String
    public var message: String
    public var hint: String?
    public var exitCode: Int32
    public var step: String?

    public init(code: String, message: String, hint: String? = nil, exitCode: Int32, step: String? = nil) {
        self.code = code
        self.message = message
        self.hint = hint
        self.exitCode = exitCode
        self.step = step
    }

    public init(_ error: HomeSignalError) {
        self.init(code: error.code, message: error.message, hint: error.hint, exitCode: error.exitCode, step: error.step)
    }

    public var error: HomeSignalError {
        HomeSignalError(code: code, message: message, hint: hint, exitCode: exitCode, step: step)
    }
}

public struct IPCResponse: Sendable, Equatable, Codable {
    public var protocolVersion: Int
    public var id: String
    public var ok: Bool
    public var result: JSONValue?
    public var error: IPCErrorBody?

    public init(id: String, ok: Bool, result: JSONValue? = nil, error: IPCErrorBody? = nil) {
        self.protocolVersion = HomeSignalVersion.protocolVersion
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
    }

    public static func success(id: String, result: JSONValue) -> IPCResponse {
        IPCResponse(id: id, ok: true, result: result)
    }

    public static func failure(id: String, error: HomeSignalError) -> IPCResponse {
        IPCResponse(id: id, ok: false, error: IPCErrorBody(error))
    }
}

public struct CapabilityReport: Sendable, Equatable, Codable {
    public var protocolVersion: Int
    public var agentVersion: String
    public var backend: String
    public var methods: [String]
    public var channels: [String]

    public init(protocolVersion: Int, agentVersion: String, backend: String, methods: [String], channels: [String]) {
        self.protocolVersion = protocolVersion
        self.agentVersion = agentVersion
        self.backend = backend
        self.methods = methods
        self.channels = channels
    }
}

public enum IPCCodec {
    public static func encodeRequest(_ request: IPCRequest) throws -> Data {
        try JSONEncoder.ipc.encode(request)
    }

    public static func decodeRequest(_ data: Data) throws -> IPCRequest {
        try JSONDecoder().decode(IPCRequest.self, from: data)
    }

    public static func encodeResponse(_ response: IPCResponse) throws -> Data {
        try JSONEncoder.ipc.encode(response)
    }

    public static func decodeResponse(_ data: Data) throws -> IPCResponse {
        try JSONDecoder().decode(IPCResponse.self, from: data)
    }
}

public struct LightNameParams: Sendable, Equatable, Codable {
    public var name: String
    public init(name: String) { self.name = name }
}

public struct LightSetParams: Sendable, Equatable, Codable {
    public var name: String
    public var patch: LightPatch
    public init(name: String, patch: LightPatch) {
        self.name = name
        self.patch = patch
    }
}

public struct BlinkParams: Sendable, Equatable, Codable {
    public var name: String
    public var times: Int
    public var color: String
    public var onMilliseconds: Int
    public var offMilliseconds: Int

    public init(name: String, times: Int, color: String, onMilliseconds: Int, offMilliseconds: Int) {
        self.name = name
        self.times = times
        self.color = color
        self.onMilliseconds = onMilliseconds
        self.offMilliseconds = offMilliseconds
    }
}

public struct DisplayShowParams: Sendable, Equatable, Codable {
    public var document: DisplayDocument
    public var present: Bool
    public var targetName: String?
    public var targetDeviceID: String?

    public init(document: DisplayDocument, present: Bool, targetName: String? = nil, targetDeviceID: String? = nil) {
        self.document = document
        self.present = present
        self.targetName = targetName
        self.targetDeviceID = targetDeviceID
    }
}

public struct PresentParams: Sendable, Equatable, Codable {
    public var present: Bool
    public init(present: Bool) { self.present = present }
}

public struct MirrorTargetParams: Sendable, Equatable, Codable {
    public var target: String
    public init(target: String) { self.target = target }
}

public struct MirrorConnectParams: Sendable, Equatable, Codable {
    public var target: String
    public var mode: String
    public var deviceID: String

    public init(target: String, mode: String, deviceID: String = "") {
        self.target = target
        self.mode = mode
        self.deviceID = deviceID
    }
}

public struct HomeBlinkParams: Sendable, Equatable, Codable {
    public var accessory: String
    public var times: Int
    public var intervalSeconds: Double
    public var color: String

    public init(accessory: String, times: Int, intervalSeconds: Double, color: String) {
        self.accessory = accessory
        self.times = times
        self.intervalSeconds = intervalSeconds
        self.color = color
    }
}

public struct InputClickParams: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var button: String
    public var clicks: Int

    public init(x: Double, y: Double, button: String, clicks: Int) {
        self.x = x
        self.y = y
        self.button = button
        self.clicks = clicks
    }
}

public struct InputMoveParams: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct InputScrollParams: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var delta: Int
    public var axis: String

    public init(x: Double, y: Double, delta: Int, axis: String) {
        self.x = x
        self.y = y
        self.delta = delta
        self.axis = axis
    }
}

public struct InputParkParams: Sendable, Equatable, Codable {
    public var display: String
    public var corner: String
    public var inset: Int

    public init(display: String, corner: String, inset: Int) {
        self.display = display
        self.corner = corner
        self.inset = inset
    }
}

public struct ScreenshotParams: Sendable, Equatable, Codable {
    public var display: String
    public var path: String?

    public init(display: String, path: String?) {
        self.display = display
        self.path = path
    }
}

public protocol AgentSending: Sendable {
    func send(_ request: IPCRequest) async throws -> IPCResponse
}

public struct PingResult: Sendable, Equatable, Codable {
    public var running: Bool
    public var version: String
    public var protocolVersion: Int

    public init(running: Bool, version: String = HomeSignalVersion.current, protocolVersion: Int = HomeSignalVersion.protocolVersion) {
        self.running = running
        self.version = version
        self.protocolVersion = protocolVersion
    }
}
