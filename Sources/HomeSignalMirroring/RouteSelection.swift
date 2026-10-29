import Foundation
import HomeSignalCore

public struct RouteCandidate: Sendable, Equatable, Codable {
    public var name: String
    public var identifier: String
    public var video: Bool
    public var screen: Bool
    public var selected: Bool
    public var local: Bool
    public var deviceType: String
    public var deviceSubtype: String
    public var featuresText: String

    public init(name: String, identifier: String, video: Bool, screen: Bool, selected: Bool, local: Bool, deviceType: String = "", deviceSubtype: String = "", featuresText: String = "") {
        self.name = name
        self.identifier = identifier
        self.video = video
        self.screen = screen
        self.selected = selected
        self.local = local
        self.deviceType = deviceType
        self.deviceSubtype = deviceSubtype
        self.featuresText = featuresText
    }
}

public struct RouteSnapshot: Sendable, Equatable, Codable {
    public var classes: [String: Bool]
    public var selectors: [String: Bool]
    public var encodings: [String: String]
    public var called: [String: Bool]
    public var devices: [RouteCandidate]
    public var screenContext: Bool
    public var featuresKnown: Bool
    public var note: String
    public var trace: [String]

    public init(classes: [String: Bool], selectors: [String: Bool], devices: [RouteCandidate], screenContext: Bool, featuresKnown: Bool, note: String, encodings: [String: String] = [:], called: [String: Bool] = [:], trace: [String] = []) {
        self.classes = classes
        self.selectors = selectors
        self.encodings = encodings
        self.called = called
        self.devices = devices
        self.screenContext = screenContext
        self.featuresKnown = featuresKnown
        self.note = note
        self.trace = trace
    }

    public var loaded: Bool {
        classes.values.contains(true)
    }
}

public protocol MediaRouteProbing: Sendable {
    func snapshot() async -> RouteSnapshot
    func setScreenRoute(identifier: String, enabled: Bool, dryRun: Bool) async throws -> RouteSnapshot
}

public protocol SessionLockReading: Sendable {
    func isScreenLocked() -> Bool
}

public struct UnlockedSession: SessionLockReading {
    public init() {}
    public func isScreenLocked() -> Bool { false }
}

public struct LockedSession: SessionLockReading {
    public init() {}
    public func isScreenLocked() -> Bool { true }
}

public enum MirrorBackendChoice: String, Sendable {
    case auto
    case routing
    case controlcenter

    public static func parse(_ raw: String?) throws -> MirrorBackendChoice {
        let text = (raw ?? "auto").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty { return .auto }
        guard let choice = MirrorBackendChoice(rawValue: text) else {
            throw HomeSignalError.usage("mirror --backend must be auto, routing, or controlcenter.")
        }
        return choice
    }
}

public enum SessionLockText {
    public static func isLocked(session: [String: String], consoleLocked: String?) -> Bool {
        let values = [session["CGSSessionScreenIsLocked"], session["IOConsoleLocked"], consoleLocked]
        return values.contains { value in
            guard let value else { return false }
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "yes", "true":
                return true
            default:
                return false
            }
        }
    }
}

public struct ProbeReport: Sendable, Equatable, Codable {
    public var snapshot: RouteSnapshot
    public var error: String?

    public init(snapshot: RouteSnapshot, error: String?) {
        self.snapshot = snapshot
        self.error = error
    }
}

public enum ObjCReturn {
    public static func returnsObject(_ encoding: String) -> Bool {
        firstType(encoding) == "@"
    }

    public static func returnsBool(_ encoding: String) -> Bool {
        guard let type = firstType(encoding) else { return false }
        return type == "B" || type == "c" || type == "C"
    }

    public static func returnsVoid(_ encoding: String) -> Bool {
        firstType(encoding) == "v"
    }

    public static func primary(_ encoding: String) -> String {
        guard let type = firstType(encoding) else { return "" }
        return String(type)
    }

    private static func firstType(_ encoding: String) -> Character? {
        let qualifiers: Set<Character> = ["r", "n", "N", "o", "O", "R", "V"]
        return encoding.first { !qualifiers.contains($0) }
    }
}

public enum ProbeOutput {
    public static func interpret(status: Int32, signaled: Bool, stdout: Data, stderr: String) -> ProbeReport {
        if !signaled, let report = try? JSONDecoder().decode(ProbeReport.self, from: stdout) {
            return report
        }
        let detail: String
        if signaled {
            detail = "home-signal-probe crashed with signal \(status). The agent stayed up."
        } else {
            let extra = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            detail = extra.isEmpty ? "home-signal-probe exited \(status) without a route report." : "home-signal-probe exited \(status). \(extra)"
        }
        return ProbeReport(
            snapshot: RouteSnapshot(classes: [:], selectors: [:], devices: [], screenContext: false, featuresKnown: false, note: detail),
            error: detail
        )
    }
}

public enum RouteSelection {
    public static func choose(_ snapshot: RouteSnapshot) -> [RouteCandidate] {
        let pool = snapshot.devices.filter { !$0.local && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard snapshot.featuresKnown else { return pool }
        return pool.filter { $0.video || $0.screen }
    }

    public static func match(target: String, deviceID: String, in devices: [RouteCandidate]) -> RouteCandidate? {
        let routes = devices.map { MirrorRoute(name: $0.name, identifier: $0.identifier, selected: $0.selected) }
        guard let found = MirrorAX.find(target: target, deviceID: deviceID, in: routes) else { return nil }
        return devices.first { $0.name == found.name && $0.identifier == found.identifier }
    }

    public static func debugText(_ snapshot: RouteSnapshot) -> String {
        var lines: [String] = []
        for name in snapshot.classes.keys.sorted() {
            lines.append("class \(name)=\(snapshot.classes[name] == true ? "yes" : "no")")
        }
        for name in snapshot.selectors.keys.sorted() {
            let encoding = snapshot.encodings[name] ?? ""
            let called = snapshot.called[name] == true ? "yes" : "no"
            lines.append("selector \(name)=\(snapshot.selectors[name] == true ? "yes" : "no") encoding=\(encoding) called=\(called)")
        }
        for device in snapshot.devices {
            var line = "device name=\(device.name) id=\(device.identifier) video=\(device.video) screen=\(device.screen) local=\(device.local) selected=\(device.selected)"
            if !device.deviceType.isEmpty { line += " type=\(device.deviceType)" }
            if !device.deviceSubtype.isEmpty { line += " subtype=\(device.deviceSubtype)" }
            if !device.featuresText.isEmpty { line += " features=\(device.featuresText)" }
            lines.append(line)
        }
        for line in snapshot.trace {
            lines.append(line)
        }
        lines.append("screenContext=\(snapshot.screenContext ? "yes" : "no")")
        lines.append("featuresKnown=\(snapshot.featuresKnown ? "yes" : "no")")
        if !snapshot.note.isEmpty {
            lines.append("note=\(snapshot.note)")
        }
        return lines.joined(separator: "\n")
    }

    public static func routes(from devices: [RouteCandidate]) -> [MirrorRoute] {
        devices.map { MirrorRoute(name: $0.name, identifier: $0.identifier, selected: $0.selected) }
    }
}
