import Foundation

public struct Log: Sendable {
    public var category: String

    public init(category: String) {
        self.category = category
    }

    public func debug(_ message: String) {
        emit("debug", message)
    }

    public func info(_ message: String) {
        emit("info", message)
    }

    public func error(_ message: String) {
        emit("error", message)
    }

    private func emit(_ level: String, _ message: String) {
        #if canImport(OSLog)
        OSLogBridge.log(level: level, category: category, message: message)
        #else
        let line = "[\(level)] [home-signal] [\(category)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        #endif
    }
}

#if canImport(OSLog)
import OSLog

enum OSLogBridge {
    static func log(level: String, category: String, message: String) {
        let logger = Logger(subsystem: "home-signal", category: category)
        switch level {
        case "error":
            logger.error("\(message, privacy: .public)")
        case "debug":
            logger.debug("\(message, privacy: .public)")
        default:
            logger.info("\(message, privacy: .public)")
        }
    }
}
#endif
