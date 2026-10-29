public struct HomeSignalError: Error, Sendable, Equatable, Codable, CustomStringConvertible {
    public var code: String
    public var message: String
    public var hint: String?
    public var exitCode: Int32

    public init(code: String, message: String, hint: String? = nil, exitCode: Int32) {
        self.code = code
        self.message = message
        self.hint = hint
        self.exitCode = exitCode
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
            message: "Displayed content does not match the request. Requested hash \(expected.contentHash) title \(expected.title ?? ""); read back hash \(actual.contentHash) title \(actual.title ?? "").",
            hint: "The command failed so this is not a successful update. Read `display status` before trying again.",
            exitCode: 4
        )
    }

    public static func usage(_ message: String) -> HomeSignalError {
        HomeSignalError(code: "usage", message: message, exitCode: 1)
    }

    public static func config(_ message: String, hint: String? = nil) -> HomeSignalError {
        HomeSignalError(code: "config", message: message, hint: hint, exitCode: 2)
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
