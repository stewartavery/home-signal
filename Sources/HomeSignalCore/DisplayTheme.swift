import Foundation

public struct DisplayTheme: Sendable, Equatable {
    public var id: String
    public var canvas: String
    public var background: String
    public var foreground: String
    public var muted: String
    public var accent: String
    public var surface: String
    public var alert: String
    public var alertForeground: String
    public var fontFamily: String

    public init(
        id: String,
        canvas: String,
        background: String,
        foreground: String,
        muted: String,
        accent: String,
        surface: String,
        alert: String,
        alertForeground: String,
        fontFamily: String
    ) {
        self.id = id
        self.canvas = canvas
        self.background = background
        self.foreground = foreground
        self.muted = muted
        self.accent = accent
        self.surface = surface
        self.alert = alert
        self.alertForeground = alertForeground
        self.fontFamily = fontFamily
    }

    func css() -> String {
        """
        html,body{background:\(canvas)}
        .stage{--background:\(background);--foreground:\(foreground);--muted:\(muted);--accent:\(accent);--surface:\(surface);--alert:\(alert);--alert-foreground:\(alertForeground);--font:\(fontFamily)}
        """
    }
}

public enum DisplayThemes {
    public static let defaultID = "default"
    public static let moonlitAutumnID = "moonlit-autumn"

    public static let neutral = DisplayTheme(
        id: defaultID,
        canvas: "#101010",
        background: "#1c1c1c",
        foreground: "#f4f4f4",
        muted: "#9b9b9b",
        accent: "#d6d6d6",
        surface: "#2a2a2a",
        alert: "#ececec",
        alertForeground: "#121212",
        fontFamily: "-apple-system,Helvetica,sans-serif"
    )

    public static let moonlitAutumn = DisplayTheme(
        id: moonlitAutumnID,
        canvas: "#0d1210",
        background: "#161410",
        foreground: "#f6f0e6",
        muted: "#b7a48e",
        accent: "#e4b56a",
        surface: "#262017",
        alert: "#d4653c",
        alertForeground: "#1c120e",
        fontFamily: "Georgia,Palatino,serif"
    )

    public static let all = [neutral, moonlitAutumn]

    public static func named(_ id: String) throws -> DisplayTheme {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else {
            throw HomeSignalError.displayRefusal("Layout spec needs a theme name.")
        }
        guard let theme = all.first(where: { $0.id == key }) else {
            throw HomeSignalError.displayRefusal("Unknown display theme \"\(key)\".")
        }
        try theme.validate()
        return theme
    }
}

extension DisplayTheme {
    func validate() throws {
        let colors = [canvas, background, foreground, muted, accent, surface, alert, alertForeground]
        guard colors.allSatisfy(Self.isHex) else {
            throw HomeSignalError.displayRefusal("Display theme \"\(id)\" has an invalid color.")
        }
        let fontOK = !fontFamily.isEmpty && !fontFamily.contains { $0 == ";" || $0 == "{" || $0 == "}" }
        guard fontOK else {
            throw HomeSignalError.displayRefusal("Display theme \"\(id)\" has an invalid font.")
        }
    }

    private static func isHex(_ value: String) -> Bool {
        guard value.count == 7, value.hasPrefix("#") else { return false }
        return value.dropFirst().allSatisfy(\.isHexDigit)
    }
}
