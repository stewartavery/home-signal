#if canImport(HomeKit)
import Foundation
import HomeKit
import HomeSignalCore

// HMHomeManager is confined to the main actor. The wrapper is Sendable so other actors can hold it.
public final class HomeKitLightBackend: LightBackend, @unchecked Sendable {
    public let backendID = "homekit"
    private let engine = HomeKitEngine()

    public init() {
        Task { @MainActor in
            self.engine.start()
        }
    }

    public func listDevices() async throws -> [LightDevice] {
        try await engine.listDevices()
    }

    public func getLight(_ name: String) async throws -> LightState {
        try await engine.getLight(name)
    }

    public func setLight(_ name: String, _ patch: LightPatch) async throws -> LightState {
        try await engine.setLight(name, patch)
    }

    public func listScenes() async throws -> [Scene] {
        try await engine.listScenes()
    }

    public func runScene(_ name: String) async throws {
        try await engine.runScene(name)
    }
}

@MainActor
final class HomeKitEngine: NSObject, HMHomeManagerDelegate {
    private let manager = HMHomeManager()
    private var ready = false
    private var waiter: CheckedContinuation<Void, Never>?

    func start() {
        manager.delegate = self
    }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        ready = true
        waiter?.resume()
        waiter = nil
    }

    func listDevices() async throws -> [LightDevice] {
        try await waitReady()
        return manager.homes.flatMap { home in
            home.accessories.filter(isLight).map { accessory in
                LightDevice(name: accessory.name, room: accessory.room?.name, type: "light")
            }
        }.sorted { $0.name < $1.name }
    }

    func getLight(_ name: String) async throws -> LightState {
        try await waitReady()
        let accessory = try findAccessory(name)
        async let power = read(accessory, HMCharacteristicTypePowerState)
        async let brightness = read(accessory, HMCharacteristicTypeBrightness)
        async let hue = read(accessory, HMCharacteristicTypeHue)
        async let saturation = read(accessory, HMCharacteristicTypeSaturation)
        async let mireds = read(accessory, HMCharacteristicTypeColorTemperature)
        return LightState(
            name: accessory.name,
            power: boolValue(try await power) ?? false,
            brightness: intValue(try await brightness),
            hue: doubleValue(try await hue),
            saturation: doubleValue(try await saturation),
            colorTemperatureKelvin: intValue(try await mireds).map { ColorTemperature.kelvin(fromMireds: $0) }
        )
    }

    func setLight(_ name: String, _ patch: LightPatch) async throws -> LightState {
        let current = try await getLight(name)
        let next = try current.applying(patch)
        let accessory = try findAccessory(name)
        if next.power && current.power == false {
            try await write(accessory, HMCharacteristicTypePowerState, value: NSNumber(value: true))
        }
        if let kelvin = next.colorTemperatureKelvin {
            let mireds = ColorTemperature.mireds(fromKelvin: kelvin)
            try await write(accessory, HMCharacteristicTypeColorTemperature, value: NSNumber(value: mireds))
        } else {
            if let hue = next.hue {
                try await write(accessory, HMCharacteristicTypeHue, value: NSNumber(value: hue))
            }
            if let saturation = next.saturation {
                try await write(accessory, HMCharacteristicTypeSaturation, value: NSNumber(value: saturation))
            }
        }
        if let brightness = next.brightness {
            try await write(accessory, HMCharacteristicTypeBrightness, value: NSNumber(value: brightness))
        }
        if next.power != current.power {
            try await write(accessory, HMCharacteristicTypePowerState, value: NSNumber(value: next.power))
        }
        return try await getLight(name)
    }

    func listScenes() async throws -> [Scene] {
        try await waitReady()
        return manager.homes.flatMap { home in
            home.actionSets.filter { $0.actionSetType == HMActionSetTypeUserDefined }.map { action in
                Scene(name: action.name)
            }
        }.sorted { $0.name < $1.name }
    }

    func runScene(_ name: String) async throws {
        try await waitReady()
        for home in manager.homes {
            if let scene = home.actionSets.first(where: { $0.name == name && $0.actionSetType == HMActionSetTypeUserDefined }) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    home.executeActionSet(scene) { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
                return
            }
        }
        throw HomeSignalError.notFound("scene", name: name)
    }

    private func waitReady() async throws {
        if ready || !manager.homes.isEmpty { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if ready || !manager.homes.isEmpty {
                continuation.resume()
            } else {
                waiter = continuation
            }
        }
    }

    private func findAccessory(_ name: String) throws -> HMAccessory {
        for home in manager.homes {
            if let accessory = home.accessories.first(where: { $0.name == name }) {
                return accessory
            }
        }
        throw HomeSignalError.notFound("light", name: name)
    }

    private func isLight(_ accessory: HMAccessory) -> Bool {
        accessory.services.contains { service in
            service.characteristics.contains { $0.characteristicType == HMCharacteristicTypeBrightness || $0.characteristicType == HMCharacteristicTypeHue }
        }
    }

    private func read(_ accessory: HMAccessory, _ type: String) async throws -> Any? {
        guard let characteristic = characteristic(accessory, type) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            characteristic.readValue { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: characteristic.value)
                }
            }
        }
    }

    private func write(_ accessory: HMAccessory, _ type: String, value: Any) async throws {
        guard let characteristic = characteristic(accessory, type) else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            characteristic.writeValue(value) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func characteristic(_ accessory: HMAccessory, _ type: String) -> HMCharacteristic? {
        accessory.services.lazy.compactMap { service in
            service.characteristics.first { $0.characteristicType == type }
        }.first
    }

    private func boolValue(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    private func intValue(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private func doubleValue(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
#endif
