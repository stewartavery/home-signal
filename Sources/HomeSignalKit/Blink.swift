import HomeSignalCore

public struct BlinkService: Sendable {
    public var sleeper: any Sleeper

    public init(sleeper: any Sleeper = TaskSleeper()) {
        self.sleeper = sleeper
    }

    public func blink(_ backend: any LightBackend, params: BlinkParams, dryRun: Bool) async throws -> BlinkResult {
        guard (1...30).contains(params.times) else {
            throw HomeSignalError.usage("Times must be from 1 to 30.")
        }
        guard (50...10_000).contains(params.onMilliseconds) else {
            throw HomeSignalError.usage("On duration must be from 50 to 10000 milliseconds.")
        }
        guard (0...10_000).contains(params.offMilliseconds) else {
            throw HomeSignalError.usage("Off duration must be from 0 to 10000 milliseconds.")
        }
        let prior = try await backend.getLight(params.name)
        if dryRun {
            return BlinkResult(name: params.name, times: params.times, color: params.color, prior: prior, restored: prior, dryRun: true)
        }
        var on = try NamedColor.patch(named: params.color)
        on.power = true
        if let brightness = prior.brightness, brightness > 0 {
            on.brightness = brightness
        } else {
            on.brightness = 100
        }
        let off = LightPatch(power: false)
        var failure: Error?
        do {
            for index in 0..<params.times {
                _ = try await backend.setLight(params.name, on)
                try await sleeper.sleep(milliseconds: params.onMilliseconds)
                _ = try await backend.setLight(params.name, off)
                if index + 1 < params.times {
                    try await sleeper.sleep(milliseconds: params.offMilliseconds)
                }
            }
        } catch {
            failure = error
        }
        do {
            _ = try await backend.setLight(params.name, prior.restorePatch())
        } catch {
            throw HomeSignalError.restoreFailed("Could not write the prior state of \(params.name): \(error)")
        }
        let restored: LightState
        do {
            restored = try await backend.getLight(params.name)
        } catch {
            throw HomeSignalError.restoreFailed("The prior state was written but \(params.name) could not be read back: \(error)")
        }
        guard LightStateMatch.restored(restored, matches: prior) else {
            throw HomeSignalError.restoreFailed("\(params.name) did not return to its prior state. Prior power \(prior.power), brightness \(String(describing: prior.brightness)), hue \(String(describing: prior.hue)), saturation \(String(describing: prior.saturation)), kelvin \(String(describing: prior.colorTemperatureKelvin)). Now power \(restored.power), brightness \(String(describing: restored.brightness)), hue \(String(describing: restored.hue)), saturation \(String(describing: restored.saturation)), kelvin \(String(describing: restored.colorTemperatureKelvin)).")
        }
        if let failure {
            throw HomeSignalError.backend("Blink stopped early (\(failure)). The prior state was restored.")
        }
        return BlinkResult(name: params.name, times: params.times, color: params.color, prior: prior, restored: restored, dryRun: false)
    }
}
