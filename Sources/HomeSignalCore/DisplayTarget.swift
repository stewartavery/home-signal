public struct DisplayTarget: Sendable, Equatable, Codable {
    public var name: String
    public var deviceID: String

    public init(name: String, deviceID: String) {
        self.name = name
        self.deviceID = deviceID
    }

    public static func resolve(overrideName: String?, overrideID: String?, config: HomeSignalConfig) throws -> DisplayTarget {
        let trimmedName = overrideName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedID = overrideID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmedName.isEmpty ? config.mirror.target : trimmedName
        let deviceID = trimmedID.isEmpty ? config.mirror.deviceID : trimmedID
        guard !name.isEmpty else {
            throw HomeSignalError.config("Set mirror.target or pass --target so the signal has an AirPlay receiver.")
        }
        return DisplayTarget(name: name, deviceID: deviceID)
    }
}

public struct AttachedDisplay: Sendable, Equatable, Codable {
    public var name: String
    public var deviceID: String
    public var width: Int
    public var height: Int
    public var originX: Int
    public var originY: Int
    public var primary: Bool

    public init(name: String, deviceID: String, width: Int, height: Int, originX: Int, originY: Int, primary: Bool) {
        self.name = name
        self.deviceID = deviceID
        self.width = width
        self.height = height
        self.originX = originX
        self.originY = originY
        self.primary = primary
    }

    public static func includingTarget(_ config: HomeSignalConfig, geometry: [DisplayBounds]) -> [AttachedDisplay] {
        var items = geometry.map { bounds in
            AttachedDisplay(
                name: bounds.name,
                deviceID: bounds.deviceID,
                width: bounds.width,
                height: bounds.height,
                originX: bounds.originX,
                originY: bounds.originY,
                primary: bounds.primary
            )
        }
        let target = config.mirror.target
        let deviceID = config.mirror.deviceID
        let already = items.contains { screen in
            screen.name == target || (!deviceID.isEmpty && screen.deviceID == deviceID)
        }
        guard !target.isEmpty, !already else { return items }
        let primary = geometry.first { $0.primary } ?? geometry.first
        let width = primary?.width ?? 1
        let height = primary?.height ?? 1
        let originX = (primary?.originX ?? 0) + width
        items.append(
            AttachedDisplay(
                name: target,
                deviceID: deviceID,
                width: width,
                height: height,
                originX: originX,
                originY: primary?.originY ?? 0,
                primary: false
            )
        )
        return items
    }
}

public struct PlacementReport: Sendable, Equatable, Codable {
    public var readback: DisplayReadback
    public var screenName: String
    public var deviceID: String
    public var fullScreen: Bool

    public init(readback: DisplayReadback, screenName: String, deviceID: String, fullScreen: Bool) {
        self.readback = readback
        self.screenName = screenName
        self.deviceID = deviceID
        self.fullScreen = fullScreen
    }
}

public enum DisplayMatch {
    public static func find(_ target: DisplayTarget, in screens: [AttachedDisplay]) -> AttachedDisplay? {
        if !target.deviceID.isEmpty,
            let byID = screens.first(where: { !$0.deviceID.isEmpty && $0.deviceID == target.deviceID })
        {
            return byID
        }
        return screens.first { $0.name == target.name }
    }
}

public struct StaticAttachedDisplays: AttachedDisplayListing {
    public var displays: [AttachedDisplay]

    public init(_ displays: [AttachedDisplay]) {
        self.displays = displays
    }

    public func attachedDisplays() async -> [AttachedDisplay] {
        displays
    }
}

public actor SimulatedDisplayPower: DisplayPowerControlling {
    public var failWake = false
    public private(set) var wakeCount = 0
    public private(set) var releaseCount = 0
    private var held = false

    public init() {}

    public func setFailWake() {
        failWake = true
    }

    public func wakeAndHold(reason: String) async throws {
        _ = reason
        if failWake {
            throw HomeSignalError.displayStep("wake", "Could not wake the display.")
        }
        if held { return }
        wakeCount += 1
        held = true
    }

    public func release() async {
        if held {
            held = false
            releaseCount += 1
        }
    }

    public func isHolding() async -> Bool {
        held
    }
}
