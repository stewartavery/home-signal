public struct HomeSignalError: Error, Sendable, Equatable, Codable, CustomStringConvertible {
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

    public var description: String {
        if let hint {
            return "\(message) \(hint)"
        }
        return message
    }

    public static func displayMismatch(expected: DisplayReadback, actual: DisplayReadback) -> HomeSignalError {
        HomeSignalError(
            code: "display_mismatch",
            message: "Step verify failed: Displayed content does not match the request. Requested hash \(expected.contentHash) title \(expected.title ?? ""); read back hash \(actual.contentHash) title \(actual.title ?? "").",
            hint: "The command failed so this is not a successful update. The window is not moved to another screen.",
            exitCode: 4,
            step: "verify"
        )
    }

    public static func displayStep(_ step: String, _ message: String, exitCode: Int32 = 4) -> HomeSignalError {
        HomeSignalError(
            code: "display_step_failed",
            message: "Step \(step) failed: \(message)",
            hint: "The page was not confirmed on the target display. The command does not show it on another screen.",
            exitCode: exitCode,
            step: step
        )
    }

    public static func usage(_ message: String) -> HomeSignalError {
        HomeSignalError(code: "usage", message: message, exitCode: 1)
    }

    public static func displayRefusal(_ message: String) -> HomeSignalError {
        let line = "Refusing to replace the screen."
        let text = message.contains(line) ? message : "\(message) \(line)"
        return usage(text)
    }

    public static func config(_ message: String, hint: String? = nil) -> HomeSignalError {
        HomeSignalError(code: "config", message: message, hint: hint, exitCode: 2)
    }

    public static func scriptBug(_ detail: String) -> HomeSignalError {
        HomeSignalError(
            code: "script_bug",
            message: "The Screen Mirroring script failed to compile. \(detail)",
            hint: "This is an internal home-signal bug, not a permissions problem.",
            exitCode: 4
        )
    }

    public static func permissionDenied(_ detail: String) -> HomeSignalError {
        HomeSignalError(
            code: "permission",
            message: "Control Center is not readable. Accessibility and Automation are required. \(detail)",
            hint: "Grant Accessibility, and Automation for System Events to control Control Center, to HomeSignalAgent. Then try again.",
            exitCode: 6
        )
    }

    public static func airPlayNotFound(target: String, seen: [String], debug: String? = nil) -> HomeSignalError {
        let list = seen.isEmpty ? "none" : seen.joined(separator: ", ")
        var hint = "Run `home-signal mirror list` to see the Screen Mirroring names."
        if let debug, !debug.isEmpty {
            hint += "\n" + debug
        }
        return HomeSignalError(
            code: "not_found",
            message: "AirPlay target \(target) was not found. Control Center showed: \(list).",
            hint: hint,
            exitCode: 3
        )
    }

    public static func deviceListTimeout(saw: [String]) -> HomeSignalError {
        let list = saw.isEmpty ? "none" : saw.joined(separator: ", ")
        return HomeSignalError(
            code: "timeout",
            message: "Screen Mirroring device list had no receiver row after 8 seconds. Saw: \(list).",
            hint: "The receiver checkboxes appear under screen-mirroring-device-list after the module opens. Pass --debug-ax to print every attribute.",
            exitCode: 7
        )
    }

    public static func screenMirroringNamesUnreadable(rows: [String]) -> HomeSignalError {
        let list = rows.isEmpty ? "none" : rows.joined(separator: "; ")
        return HomeSignalError(
            code: "backend",
            message: "Screen Mirroring showed \(rows.count) receiver row\(rows.count == 1 ? "" : "s") but no name was exposed. \(list).",
            hint: "The row identifier is an opaque id, not the receiver name. Pass --debug-ax to print AXTitle, AXLabel, AXHelp, AXValue, AXChildren, and AXCustomContent for each row.",
            exitCode: 4
        )
    }

    public static func screenMirroringUnavailable(seen: [String], debug: String? = nil) -> HomeSignalError {
        let list = seen.isEmpty ? "none" : seen.joined(separator: ", ")
        var hint = "Screen Mirroring is opened from the Control Center menu bar item, then the Screen Mirroring module. Pass --debug-ax to dump the accessibility tree."
        if let debug, !debug.isEmpty {
            hint += "\n" + debug
        }
        return HomeSignalError(
            code: "not_found",
            message: "Screen Mirroring controls were not found. Accessibility nodes: \(list).",
            hint: hint,
            exitCode: 3
        )
    }

    public static func notFound(_ kind: String, name: String) -> HomeSignalError {
        HomeSignalError(
            code: "not_found",
            message: "\(kind) \(name) was not found.",
            hint: "Run `home-signal device list` or `home-signal scene list` to see names the agent can see.",
            exitCode: 3
        )
    }

    public static func backend(_ message: String, hint: String? = nil) -> HomeSignalError {
        HomeSignalError(code: "backend", message: message, hint: hint, exitCode: 4)
    }

    public static func daemonUnavailable(_ path: String) -> HomeSignalError {
        HomeSignalError(
            code: "daemon_unavailable",
            message: "HomeSignalAgent is not running (socket \(path)).",
            hint: "Start it with `HomeSignalAgent` on the Mac, or `HomeSignalAgent --simulate` without hardware.",
            exitCode: 5
        )
    }

    public static func unsupported(_ message: String, hint: String? = nil) -> HomeSignalError {
        HomeSignalError(code: "unsupported", message: message, hint: hint, exitCode: 6)
    }

    public static func notControllable(_ name: String) -> HomeSignalError {
        HomeSignalError(
            code: "not_controllable",
            message: "Accessory \(name) is not a controllable light.",
            hint: "home blink only changes accessories that report as lights. Run `home-signal device list` to see them.",
            exitCode: 6
        )
    }

    public static func timeout(_ message: String) -> HomeSignalError {
        HomeSignalError(code: "timeout", message: message, exitCode: 7)
    }

    public static func restoreFailed(_ message: String) -> HomeSignalError {
        HomeSignalError(
            code: "restore_failed",
            message: message,
            hint: "The light may not be in its original state. Read it with `home-signal device get` and set it back.",
            exitCode: 8
        )
    }

    public static var nativeRouteUnavailable: HomeSignalError {
        HomeSignalError(
            code: "native_route_unavailable",
            message: "AVRoutePickerView cannot select a named AirPlay target without a user click.",
            hint: "Falling back to Control Center automation.",
            exitCode: 6
        )
    }
}
