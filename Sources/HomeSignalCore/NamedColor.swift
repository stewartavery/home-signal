public enum NamedColor {
    public static let names = [
        "red", "orange", "amber", "yellow", "green", "cyan", "blue", "purple", "pink", "white", "warm", "cool",
    ]

    public static func patch(named name: String) throws -> LightPatch {
        switch name.lowercased() {
        case "red":
            return hue(0, saturation: 100)
        case "orange":
            return hue(30, saturation: 100)
        case "amber":
            return hue(40, saturation: 100)
        case "yellow":
            return hue(55, saturation: 100)
        case "green":
            return hue(120, saturation: 100)
        case "cyan":
            return hue(180, saturation: 100)
        case "blue":
            return hue(240, saturation: 100)
        case "purple":
            return hue(280, saturation: 100)
        case "pink":
            return hue(330, saturation: 80)
        case "white":
            return hue(0, saturation: 0)
        case "warm":
            return kelvin(2700)
        case "cool":
            return kelvin(6500)
        default:
            throw HomeSignalError.usage(
                "Unknown color \(name). Use \(names.joined(separator: ", ")), or pass hue, saturation, and color temperature directly."
            )
        }
    }

    private static func hue(_ hue: Double, saturation: Double) -> LightPatch {
        LightPatch(hue: hue, saturation: saturation, clearColorTemperature: true)
    }

    private static func kelvin(_ kelvin: Int) -> LightPatch {
        LightPatch(colorTemperatureKelvin: kelvin, clearHueSaturation: true)
    }
}

public enum ColorTemperature {
    public static func mireds(fromKelvin kelvin: Int) -> Int {
        max(1, 1_000_000 / kelvin)
    }

    public static func kelvin(fromMireds mireds: Int) -> Int {
        guard mireds > 0 else { return 0 }
        return 1_000_000 / mireds
    }
}
