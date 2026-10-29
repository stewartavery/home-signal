import Foundation
import HomeSignalCore

public struct AXRecord: Sendable, Equatable {
    public var depth: Int
    public var role: String
    public var subrole: String
    public var identifier: String
    public var title: String
    public var description: String
    public var value: String

    public init(depth: Int, role: String, subrole: String, identifier: String, title: String, description: String, value: String) {
        self.depth = depth
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.title = title
        self.description = description
        self.value = value
    }

    public var label: String {
        if !description.isEmpty { return description }
        return title
    }
}

public enum MenuBarChoice: Sendable, Equatable {
    case screenMirroring(label: String)
    case controlCenter(label: String)
    case notFound
}

public enum MirrorAX {
    public static func parse(_ text: String) -> [AXRecord] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7, let depth = Int(fields[0]) else { return nil }
            return AXRecord(
                depth: depth,
                role: fields[1],
                subrole: fields[2],
                identifier: fields[3],
                title: fields[4],
                description: fields[5],
                value: fields[6]
            )
        }
    }

    public static func format(_ records: [AXRecord]) -> String {
        records.map { record in
            let pad = String(repeating: "  ", count: max(0, record.depth - 1))
            return "\(pad)\(record.role) subrole=\(record.subrole) id=\(record.identifier) title=\(record.title) description=\(record.description) value=\(record.value)"
        }.joined(separator: "\n")
    }

    public static func menuBarChoice(_ records: [AXRecord]) -> MenuBarChoice {
        if let item = records.first(where: { isScreenMirroringLabel($0.label) }) {
            return .screenMirroring(label: item.label)
        }
        if let item = records.first(where: { normalize($0.label) == "control center" }) {
            return .controlCenter(label: item.label)
        }
        return .notFound
    }

    public static func screenMirroringModule(_ records: [AXRecord]) -> AXRecord? {
        let controls = records.filter { isControlRole($0.role) }
        if let identified = controls.first(where: { isScreenMirroringIdentifier($0.identifier) }) {
            return identified
        }
        return controls.first { isScreenMirroringLabel($0.label) }
    }

    public static func routes(_ records: [AXRecord]) -> [MirrorRoute] {
        var seen: [String] = []
        var routes: [MirrorRoute] = []
        for record in records where isRouteRole(record.role) {
            if isScreenMirroringIdentifier(record.identifier) || isScreenMirroringLabel(record.label) {
                continue
            }
            let name = record.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = normalize(name) + "\u{0}" + record.identifier
            guard !seen.contains(key) else { continue }
            seen.append(key)
            routes.append(MirrorRoute(name: name, identifier: record.identifier, selected: isOn(record.value)))
        }
        return routes
    }

    public static func labels(_ records: [AXRecord]) -> [String] {
        var names: [String] = []
        for record in records {
            let name = record.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !names.contains(name) else { continue }
            names.append(name)
        }
        return names
    }

    public static func find(target: String, deviceID: String, in routes: [MirrorRoute]) -> MirrorRoute? {
        if !deviceID.isEmpty {
            if let byID = routes.first(where: { $0.identifier == deviceID }) {
                return byID
            }
        }
        let wanted = normalize(target)
        let wantedBase = withoutCopySuffix(wanted)
        if let exact = routes.first(where: { normalize($0.name) == wanted }) {
            return exact
        }
        return routes.first { withoutCopySuffix(normalize($0.name)) == wantedBase }
    }

    public static func normalize(_ raw: String) -> String {
        var text = raw.precomposedStringWithCanonicalMapping
        let replacements = [
            "\u{2019}": "'",
            "\u{2018}": "'",
            "\u{201B}": "'",
            "\u{2032}": "'",
            "`": "'",
            "\u{00B4}": "'",
            "\u{201C}": "\"",
            "\u{201D}": "\"",
        ]
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.lowercased()
    }

    public static func syntaxProblem(_ detail: String) -> Bool {
        let lowered = detail.lowercased()
        return lowered.contains("-2741") || lowered.contains("-2740") || lowered.contains("syntax error")
    }

    public static func permissionProblem(_ detail: String) -> Bool {
        if syntaxProblem(detail) { return false }
        let lowered = detail.lowercased()
        if lowered.contains("window 1 of process") { return true }
        if lowered.contains("not authorized to send apple events") { return true }
        if lowered.contains("not allowed assistive") { return true }
        if lowered.contains("assistive access") { return true }
        return false
    }

    public static func automationFailure(_ detail: String) -> HomeSignalError {
        if syntaxProblem(detail) {
            return HomeSignalError(
                code: "script_bug",
                message: "The Screen Mirroring script failed to compile. \(detail)",
                hint: "This is an internal home-signal bug, not a permissions problem.",
                exitCode: 4
            )
        }
        if permissionProblem(detail) {
            return HomeSignalError.permissionDenied(detail)
        }
        return HomeSignalError.backend(
            detail.isEmpty ? "Control Center automation failed." : detail,
            hint: "Pass --debug-ax to keep each accessibility step. A compile error is not a permissions failure."
        )
    }

    public static func isScreenMirroringLabel(_ raw: String) -> Bool {
        let text = normalize(raw)
        return text == "screen mirroring" || text.contains("screen mirroring")
    }

    public static func isScreenMirroringIdentifier(_ raw: String) -> Bool {
        let text = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        return text.contains("screen-mirroring") || text.contains("screenmirroring")
    }

    private static func isControlRole(_ role: String) -> Bool {
        let text = role.lowercased()
        return text.contains("button") || text.contains("checkbox") || text.contains("check box")
    }

    private static func isRouteRole(_ role: String) -> Bool {
        let text = role.lowercased()
        return text.contains("checkbox") || text.contains("check box") || text.contains("radio") || text.contains("menuitem") || text.contains("menu item") || text.contains("button")
    }

    private static func isOn(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text == "1" || text == "true" || text == "on" || text == "yes"
    }

    private static func withoutCopySuffix(_ normalized: String) -> String {
        guard let range = normalized.range(of: #" \(\d+\)$"#, options: .regularExpression) else {
            return normalized
        }
        return String(normalized[..<range.lowerBound])
    }
}

public enum DNSSDText {
    public static func instanceNames(_ output: String) -> [String] {
        var names: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard text.contains("Add") else { continue }
            guard let range = text.range(of: "_airplay._tcp", options: .caseInsensitive) else { continue }
            var name = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix(".") {
                name = name.dropFirst().trimmingCharacters(in: .whitespaces)
            }
            guard !name.isEmpty, !names.contains(name) else { continue }
            names.append(name)
        }
        return names
    }
}
