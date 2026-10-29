import Foundation

public struct Fraction: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ShortcutsConfig: Sendable, Equatable, Codable {
    public var getState: String
    public var setState: String
    public var listDevices: String
    public var listScenes: String
    public var runScene: String

    public init(getState: String, setState: String, listDevices: String, listScenes: String, runScene: String) {
        self.getState = getState
        self.setState = setState
        self.listDevices = listDevices
        self.listScenes = listScenes
        self.runScene = runScene
    }
}

public struct HTTPConfig: Sendable, Equatable, Codable {
    public var baseURL: String
    public var tokenEnv: String

    public init(baseURL: String, tokenEnv: String) {
        self.baseURL = baseURL
        self.tokenEnv = tokenEnv
    }
}

public struct HomeKitConfig: Sendable, Equatable, Codable {
    public var backend: String
    public var shortcuts: ShortcutsConfig
    public var http: HTTPConfig

    public init(backend: String, shortcuts: ShortcutsConfig, http: HTTPConfig) {
        self.backend = backend
        self.shortcuts = shortcuts
        self.http = http
    }
}

public struct DisplayConfig: Sendable, Equatable, Codable {
    public var background: String
    public var foreground: String
    public var accent: String
    public var messageSize: String
    public var titleSize: String
    public var rowSize: String
    public var displayName: String
    public var parkMouse: Bool
    public var reconnectSeconds: Double

    public init(
        background: String,
        foreground: String,
        accent: String,
        messageSize: String,
        titleSize: String,
        rowSize: String,
        displayName: String,
        parkMouse: Bool,
        reconnectSeconds: Double
    ) {
        self.background = background
        self.foreground = foreground
        self.accent = accent
        self.messageSize = messageSize
        self.titleSize = titleSize
        self.rowSize = rowSize
        self.displayName = displayName
        self.parkMouse = parkMouse
        self.reconnectSeconds = reconnectSeconds
    }
}

public struct MirrorClicks: Sendable, Equatable, Codable {
    public var chooseContent: Fraction
    public var windowOrApp: Fraction
    public var mirrorThisWindow: Fraction

    public init(chooseContent: Fraction, windowOrApp: Fraction, mirrorThisWindow: Fraction) {
        self.chooseContent = chooseContent
        self.windowOrApp = windowOrApp
        self.mirrorThisWindow = mirrorThisWindow
    }
}

public struct MirrorAbsolute: Sendable, Equatable, Codable {
    public var chooseContent: Point?
    public var windowOrApp: Point?
    public var mirrorThisWindow: Point?

    public init(chooseContent: Point? = nil, windowOrApp: Point? = nil, mirrorThisWindow: Point? = nil) {
        self.chooseContent = chooseContent
        self.windowOrApp = windowOrApp
        self.mirrorThisWindow = mirrorThisWindow
    }

    public var isComplete: Bool {
        chooseContent != nil && windowOrApp != nil && mirrorThisWindow != nil
    }
}

public struct MirrorConfig: Sendable, Equatable, Codable {
    public var target: String
    public var deviceID: String
    public var mode: String
    public var settleSeconds: Double
    public var clicks: MirrorClicks
    public var absolute: MirrorAbsolute

    public init(
        target: String,
        deviceID: String,
        mode: String,
        settleSeconds: Double,
        clicks: MirrorClicks,
        absolute: MirrorAbsolute
    ) {
        self.target = target
        self.deviceID = deviceID
        self.mode = mode
        self.settleSeconds = settleSeconds
        self.clicks = clicks
        self.absolute = absolute
    }
}

public struct InputConfig: Sendable, Equatable, Codable {
    public var parkDisplay: String
    public var parkCorner: String
    public var parkInset: Int

    public init(parkDisplay: String, parkCorner: String, parkInset: Int) {
        self.parkDisplay = parkDisplay
        self.parkCorner = parkCorner
        self.parkInset = parkInset
    }
}

public struct AgentConfig: Sendable, Equatable, Codable {
    public var socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }
}

public struct SimulatedDevice: Sendable, Equatable, Codable {
    public var name: String
    public var room: String?
    public var power: Bool
    public var brightness: Int?
    public var hue: Double?
    public var saturation: Double?
    public var colorTemperatureKelvin: Int?

    public init(
        name: String,
        room: String? = nil,
        power: Bool,
        brightness: Int? = nil,
        hue: Double? = nil,
        saturation: Double? = nil,
        colorTemperatureKelvin: Int? = nil
    ) {
        self.name = name
        self.room = room
        self.power = power
        self.brightness = brightness
        self.hue = hue
        self.saturation = saturation
        self.colorTemperatureKelvin = colorTemperatureKelvin
    }

    public var state: LightState {
        LightState(
            name: name,
            power: power,
            brightness: brightness,
            hue: hue,
            saturation: saturation,
            colorTemperatureKelvin: colorTemperatureKelvin
        )
    }
}

public struct SimulatedConfig: Sendable, Equatable, Codable {
    public var devices: [SimulatedDevice]
    public var scenes: [String]

    public init(devices: [SimulatedDevice], scenes: [String]) {
        self.devices = devices
        self.scenes = scenes
    }
}

public struct HomeSignalConfig: Sendable, Equatable, Codable {
    public var version: Int
    public var homekit: HomeKitConfig
    public var display: DisplayConfig
    public var mirror: MirrorConfig
    public var displays: [DisplayBounds]
    public var input: InputConfig
    public var agent: AgentConfig
    public var simulated: SimulatedConfig

    public init(
        version: Int,
        homekit: HomeKitConfig,
        display: DisplayConfig,
        mirror: MirrorConfig,
        displays: [DisplayBounds],
        input: InputConfig,
        agent: AgentConfig,
        simulated: SimulatedConfig
    ) {
        self.version = version
        self.homekit = homekit
        self.display = display
        self.mirror = mirror
        self.displays = displays
        self.input = input
        self.agent = agent
        self.simulated = simulated
    }

    public static let standard: HomeSignalConfig = {
        do {
            return try ConfigLoader.parse(ConfigText.example)
        } catch {
            fatalError("Built-in config failed to parse: \(error)")
        }
    }()
}

public enum ConfigText {
    public static let example = """
    version = 1

    # Copy to ~/.config/home-signal/config.toml and replace every placeholder.
    # Device names, AirPlay targets, display sizes, and click positions come from
    # your Home app and from `home-signal displays`. These values are examples only.

    [homekit]
    backend = "homekit"

    [homekit.shortcuts]
    get_state = "HomeSignal Get State"
    set_state = "HomeSignal Set State"
    list_devices = "HomeSignal List Devices"
    list_scenes = "HomeSignal List Scenes"
    run_scene = "HomeSignal Run Scene"

    [homekit.http]
    base_url = "http://127.0.0.1:8581"
    token_env = "HOME_SIGNAL_HTTP_TOKEN"

    [display]
    background = "#000000"
    foreground = "#ffffff"
    accent = "#99ccff"
    message_size = "10vw"
    title_size = "6vw"
    row_size = "3.2vw"
    display_name = "main"
    park_mouse = true
    reconnect_seconds = 15

    [mirror]
    target = "TV"
    device_id = ""
    mode = "window"
    settle_seconds = 3

    [mirror.clicks]
    choose_content = { x = 0.50, y = 0.78 }
    window_or_app = { x = 0.50, y = 0.55 }
    mirror_this_window = { x = 0.50, y = 0.42 }

    [[displays]]
    name = "main"
    width = 1920
    height = 1080
    origin_x = 0
    origin_y = 0
    primary = true

    [[displays]]
    name = "external"
    width = 1920
    height = 1080
    origin_x = 1920
    origin_y = 0
    primary = false

    [input]
    park_display = "main"
    park_corner = "bottom-right"
    park_inset = 12

    [agent]
    socket_path = "~/.local/share/home-signal/agent.sock"

    [simulated]
    scenes = ["Scene A"]

    [[simulated.devices]]
    name = "Lamp 1"
    room = "Room A"
    power = true
    brightness = 40
    hue = 30.0
    saturation = 80.0

    [[simulated.devices]]
    name = "Lamp 2"
    room = "Room B"
    power = false
    brightness = 100
    color_temperature_kelvin = 2700
    """
}

public enum ConfigLoader {
    public static func load(explicitPath: String?) throws -> HomeSignalConfig {
        if let explicitPath {
            let path = HomeSignalPaths.expand(explicitPath)
            guard FileManager.default.fileExists(atPath: path) else {
                throw HomeSignalError.config("Config file not found: \(path)")
            }
            return try parse(String(contentsOfFile: path, encoding: .utf8))
        }
        let path = HomeSignalPaths.configPath()
        guard FileManager.default.fileExists(atPath: path) else {
            return .standard
        }
        return try parse(String(contentsOfFile: path, encoding: .utf8))
    }

    public static func parse(_ text: String) throws -> HomeSignalConfig {
        let root: [String: TOMLValue]
        do {
            root = try TOMLParser.parse(text)
        } catch let error as TOMLParseError {
            throw HomeSignalError.config(String(describing: error))
        }
        let defaults = builtinDefaults
        let version = root["version"]?.int ?? 0
        guard version == 1 else {
            throw HomeSignalError.config("Unsupported config version \(version). This build reads version 1.")
        }
        let homekitTable = root["homekit"]?.table
        let backend = homekitTable?["backend"]?.string ?? defaults.homekit.backend
        guard ["homekit", "shortcuts", "http", "simulated"].contains(backend) else {
            throw HomeSignalError.config("homekit.backend must be homekit, shortcuts, http, or simulated.")
        }
        let shortcutsTable = homekitTable?["shortcuts"]?.table
        let httpTable = homekitTable?["http"]?.table
        let displayTable = root["display"]?.table
        let mirrorTable = root["mirror"]?.table
        let clicksTable = mirrorTable?["clicks"]?.table
        let absoluteTable = mirrorTable?["absolute"]?.table
        let inputTable = root["input"]?.table
        let agentTable = root["agent"]?.table
        let simulatedTable = root["simulated"]?.table

        let mode = try MirrorMode.validate(mirrorTable?["mode"]?.string ?? defaults.mirror.mode)
        let clicks = MirrorClicks(
            chooseContent: try fraction(clicksTable, "choose_content", fallback: defaults.mirror.clicks.chooseContent),
            windowOrApp: try fraction(clicksTable, "window_or_app", fallback: defaults.mirror.clicks.windowOrApp),
            mirrorThisWindow: try fraction(clicksTable, "mirror_this_window", fallback: defaults.mirror.clicks.mirrorThisWindow)
        )
        let displays = try displayList(root["displays"]) ?? defaults.displays
        for screen in displays {
            guard screen.width > 0, screen.height > 0 else {
                throw HomeSignalError.config("Display \(screen.name) must have a positive width and height.")
            }
            guard !screen.name.isEmpty else {
                throw HomeSignalError.config("A display is missing a name.")
            }
        }
        let simulated = try simulatedConfig(simulatedTable) ?? defaults.simulated
        let config = HomeSignalConfig(
            version: 1,
            homekit: HomeKitConfig(
                backend: backend,
                shortcuts: ShortcutsConfig(
                    getState: shortcutsTable?["get_state"]?.string ?? defaults.homekit.shortcuts.getState,
                    setState: shortcutsTable?["set_state"]?.string ?? defaults.homekit.shortcuts.setState,
                    listDevices: shortcutsTable?["list_devices"]?.string ?? defaults.homekit.shortcuts.listDevices,
                    listScenes: shortcutsTable?["list_scenes"]?.string ?? defaults.homekit.shortcuts.listScenes,
                    runScene: shortcutsTable?["run_scene"]?.string ?? defaults.homekit.shortcuts.runScene
                ),
                http: HTTPConfig(
                    baseURL: httpTable?["base_url"]?.string ?? defaults.homekit.http.baseURL,
                    tokenEnv: httpTable?["token_env"]?.string ?? defaults.homekit.http.tokenEnv
                )
            ),
            display: DisplayConfig(
                background: displayTable?["background"]?.string ?? defaults.display.background,
                foreground: displayTable?["foreground"]?.string ?? defaults.display.foreground,
                accent: displayTable?["accent"]?.string ?? defaults.display.accent,
                messageSize: displayTable?["message_size"]?.string ?? defaults.display.messageSize,
                titleSize: displayTable?["title_size"]?.string ?? defaults.display.titleSize,
                rowSize: displayTable?["row_size"]?.string ?? defaults.display.rowSize,
                displayName: displayTable?["display_name"]?.string ?? defaults.display.displayName,
                parkMouse: displayTable?["park_mouse"]?.bool ?? defaults.display.parkMouse,
                reconnectSeconds: displayTable?["reconnect_seconds"]?.double ?? defaults.display.reconnectSeconds
            ),
            mirror: MirrorConfig(
                target: mirrorTable?["target"]?.string ?? defaults.mirror.target,
                deviceID: mirrorTable?["device_id"]?.string ?? defaults.mirror.deviceID,
                mode: mode,
                settleSeconds: mirrorTable?["settle_seconds"]?.double ?? defaults.mirror.settleSeconds,
                clicks: clicks,
                absolute: absolute(absoluteTable) ?? defaults.mirror.absolute
            ),
            displays: displays,
            input: InputConfig(
                parkDisplay: inputTable?["park_display"]?.string ?? defaults.input.parkDisplay,
                parkCorner: inputTable?["park_corner"]?.string ?? defaults.input.parkCorner,
                parkInset: inputTable?["park_inset"]?.int ?? defaults.input.parkInset
            ),
            agent: AgentConfig(
                socketPath: agentTable?["socket_path"]?.string ?? defaults.agent.socketPath
            ),
            simulated: simulated
        )
        let corner = config.input.parkCorner
        guard ["bottom-right", "bottom-left", "top-right", "top-left"].contains(corner) else {
            throw HomeSignalError.config("input.park_corner must be a screen corner such as bottom-right.")
        }
        guard config.mirror.settleSeconds >= 0 else {
            throw HomeSignalError.config("mirror.settle_seconds must be zero or greater.")
        }
        guard !config.mirror.target.isEmpty else {
            throw HomeSignalError.config("mirror.target must be the AirPlay device name shown in Control Center.")
        }
        guard config.display.reconnectSeconds > 0, config.display.reconnectSeconds <= 120 else {
            throw HomeSignalError.config("display.reconnect_seconds must be greater than 0 and at most 120.")
        }
        return config
    }

    private static func fraction(_ table: [String: TOMLValue]?, _ key: String, fallback: Fraction) throws -> Fraction {
        guard let value = table?[key] else { return fallback }
        guard let fields = value.table, let x = fields["x"]?.double, let y = fields["y"]?.double else {
            throw HomeSignalError.config("\(key) must be an inline table with x and y.")
        }
        guard (0...1).contains(x), (0...1).contains(y) else {
            throw HomeSignalError.config("\(key) fractions must be from 0 to 1.")
        }
        return Fraction(x: x, y: y)
    }

    private static func absolute(_ table: [String: TOMLValue]?) -> MirrorAbsolute? {
        guard let table else { return nil }
        return MirrorAbsolute(
            chooseContent: point(table["choose_content"]),
            windowOrApp: point(table["window_or_app"]),
            mirrorThisWindow: point(table["mirror_this_window"])
        )
    }

    private static func point(_ value: TOMLValue?) -> Point? {
        guard let fields = value?.table, let x = fields["x"]?.double, let y = fields["y"]?.double else { return nil }
        return Point(x: x, y: y)
    }

    private static func displayList(_ value: TOMLValue?) throws -> [DisplayBounds]? {
        guard let value else { return nil }
        guard let rows = value.array else {
            throw HomeSignalError.config("displays must be an array of tables.")
        }
        return try rows.map { row in
            guard let table = row.table,
                let name = table["name"]?.string,
                let width = table["width"]?.int,
                let height = table["height"]?.int
            else {
                throw HomeSignalError.config("Each display needs name, width, and height.")
            }
            return DisplayBounds(
                name: name,
                width: width,
                height: height,
                originX: table["origin_x"]?.int ?? 0,
                originY: table["origin_y"]?.int ?? 0,
                primary: table["primary"]?.bool ?? false
            )
        }
    }

    private static func simulatedConfig(_ table: [String: TOMLValue]?) throws -> SimulatedConfig? {
        guard let table else { return nil }
        let scenes = table["scenes"]?.array?.compactMap(\.string) ?? []
        let devices: [SimulatedDevice]
        if let rows = table["devices"]?.array {
            devices = try rows.map { row in
                guard let fields = row.table, let name = fields["name"]?.string, !name.isEmpty else {
                    throw HomeSignalError.config("Each simulated device needs a name.")
                }
                return SimulatedDevice(
                    name: name,
                    room: fields["room"]?.string,
                    power: fields["power"]?.bool ?? false,
                    brightness: fields["brightness"]?.int,
                    hue: fields["hue"]?.double,
                    saturation: fields["saturation"]?.double,
                    colorTemperatureKelvin: fields["color_temperature_kelvin"]?.int
                )
            }
        } else {
            devices = []
        }
        return SimulatedConfig(devices: devices, scenes: scenes)
    }
}

private let builtinDefaults = HomeSignalConfig(
    version: 1,
    homekit: HomeKitConfig(
        backend: "homekit",
        shortcuts: ShortcutsConfig(
            getState: "HomeSignal Get State",
            setState: "HomeSignal Set State",
            listDevices: "HomeSignal List Devices",
            listScenes: "HomeSignal List Scenes",
            runScene: "HomeSignal Run Scene"
        ),
        http: HTTPConfig(baseURL: "http://127.0.0.1:8581", tokenEnv: "HOME_SIGNAL_HTTP_TOKEN")
    ),
    display: DisplayConfig(
        background: "#000000",
        foreground: "#ffffff",
        accent: "#99ccff",
        messageSize: "10vw",
        titleSize: "6vw",
        rowSize: "3.2vw",
        displayName: "main",
        parkMouse: true,
        reconnectSeconds: 15
    ),
    mirror: MirrorConfig(
        target: "TV",
        deviceID: "",
        mode: "window",
        settleSeconds: 3,
        clicks: MirrorClicks(
            chooseContent: Fraction(x: 0.50, y: 0.78),
            windowOrApp: Fraction(x: 0.50, y: 0.55),
            mirrorThisWindow: Fraction(x: 0.50, y: 0.42)
        ),
        absolute: MirrorAbsolute()
    ),
    displays: [
        DisplayBounds(name: "main", width: 1920, height: 1080, originX: 0, originY: 0, primary: true),
        DisplayBounds(name: "external", width: 1920, height: 1080, originX: 1920, originY: 0, primary: false),
    ],
    input: InputConfig(parkDisplay: "main", parkCorner: "bottom-right", parkInset: 12),
    agent: AgentConfig(socketPath: "~/.local/share/home-signal/agent.sock"),
    simulated: SimulatedConfig(
        devices: [
            SimulatedDevice(name: "Lamp 1", room: "Room A", power: true, brightness: 40, hue: 30, saturation: 80),
            SimulatedDevice(name: "Lamp 2", room: "Room B", power: false, brightness: 100, colorTemperatureKelvin: 2700),
        ],
        scenes: ["Scene A"]
    )
)
