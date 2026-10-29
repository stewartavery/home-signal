import Foundation

public enum HomeSignalPaths {
    public static func homeDirectory() -> String {
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
            return home
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    public static func expand(_ path: String) -> String {
        if path == "~" {
            return homeDirectory()
        }
        if path.hasPrefix("~/") {
            return homeDirectory() + path.dropFirst(1)
        }
        return path
    }

    public static func configPath() -> String {
        expand("~/.config/home-signal/config.toml")
    }

    public static func defaultSocketPath() -> String {
        expand("~/.local/share/home-signal/agent.sock")
    }

    public static func screenshotDirectory() -> String {
        expand("~/.local/share/home-signal/screenshots")
    }
}
