public struct LightState: Sendable, Equatable {
    public var name: String
    public var power: Bool
    public var brightness: Int?
    public var hue: Double?
    public var saturation: Double?
    public var colorTemperatureKelvin: Int?

    public init(
        name: String,
        power: Bool,
        brightness: Int? = nil,
        hue: Double? = nil,
        saturation: Double? = nil,
        colorTemperatureKelvin: Int? = nil
    ) {
        self.name = name
        self.power = power
        self.brightness = brightness
        self.hue = hue
        self.saturation = saturation
        self.colorTemperatureKelvin = colorTemperatureKelvin
    }
}

extension LightState: Codable {
    enum CodingKeys: String, CodingKey {
        case name
        case power
        case brightness
        case hue
        case saturation
        case colorTemperatureKelvin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        power = try container.decode(Bool.self, forKey: .power)
        brightness = try container.decodeIfPresent(Int.self, forKey: .brightness)
        hue = try container.decodeIfPresent(Double.self, forKey: .hue)
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation)
        colorTemperatureKelvin = try container.decodeIfPresent(Int.self, forKey: .colorTemperatureKelvin)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(power, forKey: .power)
        try container.encode(brightness, forKey: .brightness)
        try container.encode(hue, forKey: .hue)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(colorTemperatureKelvin, forKey: .colorTemperatureKelvin)
    }
}

public struct LightPatch: Sendable, Equatable {
    public var power: Bool?
    public var brightness: Int?
    public var hue: Double?
    public var saturation: Double?
    public var colorTemperatureKelvin: Int?
    public var color: String?
    public var clearHueSaturation: Bool
    public var clearColorTemperature: Bool

    public init(
        power: Bool? = nil,
        brightness: Int? = nil,
        hue: Double? = nil,
        saturation: Double? = nil,
        colorTemperatureKelvin: Int? = nil,
        color: String? = nil,
        clearHueSaturation: Bool = false,
        clearColorTemperature: Bool = false
    ) {
        self.power = power
        self.brightness = brightness
        self.hue = hue
        self.saturation = saturation
        self.colorTemperatureKelvin = colorTemperatureKelvin
        self.color = color
        self.clearHueSaturation = clearHueSaturation
        self.clearColorTemperature = clearColorTemperature
    }
}

extension LightPatch: Codable {
    enum CodingKeys: String, CodingKey {
        case power
        case brightness
        case hue
        case saturation
        case colorTemperatureKelvin
        case color
        case clearHueSaturation
        case clearColorTemperature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        power = try container.decodeIfPresent(Bool.self, forKey: .power)
        brightness = try container.decodeIfPresent(Int.self, forKey: .brightness)
        hue = try container.decodeIfPresent(Double.self, forKey: .hue)
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation)
        colorTemperatureKelvin = try container.decodeIfPresent(Int.self, forKey: .colorTemperatureKelvin)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        clearHueSaturation = try container.decodeIfPresent(Bool.self, forKey: .clearHueSaturation) ?? false
        clearColorTemperature = try container.decodeIfPresent(Bool.self, forKey: .clearColorTemperature) ?? false
    }
}

extension LightPatch {
    public func resolved() throws -> LightPatch {
        guard let color else { return self }
        var base = try NamedColor.patch(named: color)
        if let power { base.power = power }
        if let brightness { base.brightness = brightness }
        if hue != nil {
            base.hue = hue
            base.clearColorTemperature = true
        }
        if saturation != nil {
            base.saturation = saturation
        }
        if colorTemperatureKelvin != nil {
            base.colorTemperatureKelvin = colorTemperatureKelvin
            base.clearHueSaturation = true
            base.clearColorTemperature = false
            base.hue = nil
            base.saturation = nil
        }
        base.color = nil
        return base
    }
}

extension LightState {
    public func applying(_ patch: LightPatch) throws -> LightState {
        let patch = try patch.resolved()
        var next = self
        if let power = patch.power { next.power = power }
        if let brightness = patch.brightness {
            guard (0...100).contains(brightness) else {
                throw HomeSignalError.usage("Brightness must be from 0 to 100.")
            }
            next.brightness = brightness
        }
        if patch.clearHueSaturation {
            next.hue = nil
            next.saturation = nil
        }
        if patch.clearColorTemperature {
            next.colorTemperatureKelvin = nil
        }
        if let hue = patch.hue {
            guard (0...360).contains(hue) else {
                throw HomeSignalError.usage("Hue must be from 0 to 360.")
            }
            next.hue = hue
        }
        if let saturation = patch.saturation {
            guard (0...100).contains(saturation) else {
                throw HomeSignalError.usage("Saturation must be from 0 to 100.")
            }
            next.saturation = saturation
        }
        if let kelvin = patch.colorTemperatureKelvin {
            guard (1000...20000).contains(kelvin) else {
                throw HomeSignalError.usage("Color temperature must be from 1000 to 20000 Kelvin.")
            }
            next.colorTemperatureKelvin = kelvin
        }
        return next
    }

    public func restorePatch() -> LightPatch {
        let colorTemperatureOnly = colorTemperatureKelvin != nil && hue == nil && saturation == nil
        let hueOnly = hue != nil && colorTemperatureKelvin == nil
        return LightPatch(
            power: power,
            brightness: brightness,
            hue: hue,
            saturation: saturation,
            colorTemperatureKelvin: colorTemperatureKelvin,
            clearHueSaturation: colorTemperatureOnly,
            clearColorTemperature: hueOnly
        )
    }
}

public enum LightStateMatch {
    public static func restored(_ actual: LightState, matches prior: LightState) -> Bool {
        guard actual.power == prior.power else { return false }
        if prior.brightness != nil && actual.brightness != prior.brightness { return false }
        if let expected = prior.hue {
            guard let got = actual.hue, abs(got - expected) <= 1 else { return false }
        }
        if let expected = prior.saturation {
            guard let got = actual.saturation, abs(got - expected) <= 1 else { return false }
        }
        if let expected = prior.colorTemperatureKelvin {
            guard let got = actual.colorTemperatureKelvin, abs(got - expected) <= 75 else { return false }
        }
        return true
    }
}

public struct LightDevice: Sendable, Equatable, Codable {
    public var name: String
    public var room: String?
    public var type: String

    public init(name: String, room: String? = nil, type: String = "light") {
        self.name = name
        self.room = room
        self.type = type
    }
}

public struct Scene: Sendable, Equatable, Codable {
    public var name: String
    public var room: String?

    public init(name: String, room: String? = nil) {
        self.name = name
        self.room = room
    }
}

public struct SceneRunResult: Sendable, Equatable, Codable {
    public var name: String
    public var ran: Bool

    public init(name: String, ran: Bool) {
        self.name = name
        self.ran = ran
    }
}

public struct ScheduleRow: Sendable, Equatable, Codable {
    public var time: String
    public var label: String

    public init(time: String, label: String) {
        self.time = time
        self.label = label
    }
}

public struct DisplayDocument: Sendable, Equatable, Codable {
    public var kind: String
    public var title: String?
    public var message: String?
    public var rows: [ScheduleRow]
    public var html: String?
    public var background: String
    public var foreground: String
    public var accent: String
    public var messageSize: String
    public var titleSize: String
    public var rowSize: String

    public init(
        kind: String,
        title: String? = nil,
        message: String? = nil,
        rows: [ScheduleRow] = [],
        html: String? = nil,
        background: String,
        foreground: String,
        accent: String,
        messageSize: String,
        titleSize: String,
        rowSize: String
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.rows = rows
        self.html = html
        self.background = background
        self.foreground = foreground
        self.accent = accent
        self.messageSize = messageSize
        self.titleSize = titleSize
        self.rowSize = rowSize
    }
}

public enum DisplayKind {
    public static let message = "message"
    public static let schedule = "schedule"
    public static let html = "html"
    public static let layout = "layout"
    public static let clear = "clear"
}

public struct DisplayReadback: Sendable, Equatable, Codable {
    public var contentHash: String
    public var title: String?
    public var kind: String

    public init(contentHash: String, title: String?, kind: String) {
        self.contentHash = contentHash
        self.title = title
        self.kind = kind
    }
}

public struct DisplayShowResult: Sendable, Equatable, Codable {
    public var contentHash: String
    public var title: String?
    public var kind: String
    public var verified: Bool
    public var target: String
    public var deviceID: String
    public var screen: String
    public var fullScreen: Bool
    public var onTarget: Bool
    public var holdingWake: Bool
    public var dryRun: Bool
    public var attached: [String]

    public init(
        contentHash: String,
        title: String?,
        kind: String,
        verified: Bool,
        target: String,
        deviceID: String,
        screen: String,
        fullScreen: Bool,
        onTarget: Bool,
        holdingWake: Bool,
        dryRun: Bool,
        attached: [String]
    ) {
        self.contentHash = contentHash
        self.title = title
        self.kind = kind
        self.verified = verified
        self.target = target
        self.deviceID = deviceID
        self.screen = screen
        self.fullScreen = fullScreen
        self.onTarget = onTarget
        self.holdingWake = holdingWake
        self.dryRun = dryRun
        self.attached = attached
    }
}

public struct Point: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct DisplayBounds: Sendable, Equatable, Codable {
    public var name: String
    public var width: Int
    public var height: Int
    public var originX: Int
    public var originY: Int
    public var primary: Bool
    public var deviceID: String

    public init(name: String, width: Int, height: Int, originX: Int, originY: Int, primary: Bool, deviceID: String = "") {
        self.name = name
        self.width = width
        self.height = height
        self.originX = originX
        self.originY = originY
        self.primary = primary
        self.deviceID = deviceID
    }
}

public struct PanelBounds: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct MirrorStatus: Sendable, Equatable, Codable {
    public var target: String
    public var connected: Bool
    public var mode: String?
    public var changed: Bool
    public var points: [Point]?

    public init(target: String, connected: Bool, mode: String? = nil, changed: Bool, points: [Point]? = nil) {
        self.target = target
        self.connected = connected
        self.mode = mode
        self.changed = changed
        self.points = points
    }
}

public struct CaptureResult: Sendable, Equatable, Codable {
    public var path: String
    public var display: String
    public var width: Int
    public var height: Int

    public init(path: String, display: String, width: Int, height: Int) {
        self.path = path
        self.display = display
        self.width = width
        self.height = height
    }
}

public struct BlinkResult: Sendable, Equatable, Codable {
    public var name: String
    public var times: Int
    public var color: String
    public var prior: LightState
    public var restored: LightState
    public var dryRun: Bool

    public init(name: String, times: Int, color: String, prior: LightState, restored: LightState, dryRun: Bool) {
        self.name = name
        self.times = times
        self.color = color
        self.prior = prior
        self.restored = restored
        self.dryRun = dryRun
    }
}

public enum MirrorMode {
    public static let window = "window"
    public static let display = "display"
    public static func validate(_ mode: String) throws -> String {
        let value = mode.lowercased()
        guard value == window || value == Self.display else {
            throw HomeSignalError.usage("Mirror mode must be \"window\" or \"display\".")
        }
        return value
    }
}
