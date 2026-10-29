import HomeSignalCore

public actor SimulatedLightBackend: LightBackend {
    public let backendID = "simulated"
    private var lights: [String: LightState]
    private var rooms: [String: String]
    private var scenes: [Scene]
    private var ran: [String] = []

    public init(config: SimulatedConfig) {
        var lights: [String: LightState] = [:]
        var rooms: [String: String] = [:]
        for device in config.devices {
            lights[device.name] = device.state
            if let room = device.room {
                rooms[device.name] = room
            }
        }
        self.lights = lights
        self.rooms = rooms
        self.scenes = config.scenes.map { Scene(name: $0) }
    }

    public func listDevices() async -> [LightDevice] {
        lights.keys.sorted().map { name in
            LightDevice(name: name, room: rooms[name], type: "light")
        }
    }

    public func getLight(_ name: String) async throws -> LightState {
        guard let state = lights[name] else {
            throw HomeSignalError.notFound("light", name: name)
        }
        return state
    }

    public func setLight(_ name: String, _ patch: LightPatch) async throws -> LightState {
        guard let current = lights[name] else {
            throw HomeSignalError.notFound("light", name: name)
        }
        let next = try current.applying(patch)
        lights[name] = next
        return next
    }

    public func listScenes() async -> [Scene] {
        scenes.sorted { $0.name < $1.name }
    }

    public func runScene(_ name: String) async throws {
        guard scenes.contains(where: { $0.name == name }) else {
            throw HomeSignalError.notFound("scene", name: name)
        }
        ran.append(name)
    }

    public func ranScenes() -> [String] {
        ran
    }
}
