import Foundation
import HomeSignalCore

public struct HTTPLightBackend: LightBackend {
    public let backendID = "http"
    private let baseURL: URL
    private let tokenEnv: String
    private let sender: any HTTPSending
    private let environment: [String: String]

    public init(config: HTTPConfig, sender: any HTTPSending = URLSessionHTTP(), environment: [String: String]? = nil) throws {
        guard let url = URL(string: config.baseURL) else {
            throw HomeSignalError.config("homekit.http.base_url is not a URL.")
        }
        self.baseURL = url
        self.tokenEnv = config.tokenEnv
        self.sender = sender
        self.environment = environment ?? ProcessInfo.processInfo.environment
    }

    public func listDevices() async throws -> [LightDevice] {
        try await send(method: "GET", path: "v1/devices", body: nil, as: [LightDevice].self)
    }

    public func getLight(_ name: String) async throws -> LightState {
        try await send(method: "GET", path: "v1/devices/\(encode(name))/state", body: nil, as: LightState.self)
    }

    public func setLight(_ name: String, _ patch: LightPatch) async throws -> LightState {
        let body = try JSONEncoder.ipc.encode(patch.resolved())
        return try await send(method: "PUT", path: "v1/devices/\(encode(name))/state", body: body, as: LightState.self)
    }

    public func listScenes() async throws -> [Scene] {
        try await send(method: "GET", path: "v1/scenes", body: nil, as: [Scene].self)
    }

    public func runScene(_ name: String) async throws {
        _ = try await send(method: "POST", path: "v1/scenes/\(encode(name))/run", body: nil, as: SceneRunResult.self)
    }

    private func encode(_ name: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }

    private func send<T: Decodable>(method: String, path: String, body: Data?, as type: T.Type) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let token = environment[tokenEnv]
        let result: HTTPResult
        do {
            result = try await sender.send(url: url, method: method, body: body, bearer: token)
        } catch {
            throw HomeSignalError.backend("HTTP request failed: \(error)")
        }
        if result.status == 404 {
            throw HomeSignalError.notFound("device", name: path)
        }
        guard (200..<300).contains(result.status) else {
            let detail = String(decoding: result.body, as: UTF8.self)
            throw HomeSignalError.backend("HTTP \(result.status) for \(method) \(path). \(detail)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: result.body)
        } catch {
            throw HomeSignalError.backend("HTTP response was not the expected JSON.")
        }
    }
}
