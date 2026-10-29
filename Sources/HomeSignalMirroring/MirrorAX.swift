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

public struct AXElement: Sendable, Equatable {
    public var role: String
    public var attributes: [String: String]
    public var children: [AXElement]

    public init(role: String, attributes: [String: String], children: [AXElement] = []) {
        self.role = role
        self.attributes = attributes
        self.children = children
    }

    public func attribute(_ key: String) -> String {
        if let value = attributes[key] { return value }
        if let pair = attributes.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            return pair.value
        }
        return ""
    }
}

public struct DeviceListRead: Sendable, Equatable {
    public var routes: [MirrorRoute]
    public var checkboxCount: Int
    public var unnamed: [String]

    public init(routes: [MirrorRoute], checkboxCount: Int, unnamed: [String]) {
        self.routes = routes
        self.checkboxCount = checkboxCount
        self.unnamed = unnamed
    }
}

public protocol ScreenMirroringReading: Sendable {
    func snapshot() async throws -> AXElement
}

public struct EmptyScreenMirroringReader: ScreenMirroringReading {
    public init() {}

    public func snapshot() async throws -> AXElement {
        AXElement(role: "AXWindow", attributes: ["AXTitle": "Control Center"], children: [])
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

    public static let screenMirroringModuleID = "controlcenter-screen-mirroring"
    public static let deviceListID = "screen-mirroring-device-list"

    public static func screenMirroringModule(_ records: [AXRecord]) -> AXRecord? {
        if let exact = records.first(where: { $0.identifier == screenMirroringModuleID }) {
            return exact
        }
        return records.first { isScreenMirroringLabel($0.title) || isScreenMirroringLabel($0.description) }
    }

    public static func routes(_ records: [AXRecord]) -> [MirrorRoute] {
        var seen: [String] = []
        var routes: [MirrorRoute] = []
        for record in records {
            let ident = record.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let folded = ident.lowercased()
            if folded == screenMirroringModuleID || folded.hasPrefix("controlcenter-") || folded.hasSuffix("-header") || folded.hasSuffix("-preferences") {
                continue
            }
            guard isRouteRole(record.role) || nameFromIdentifier(ident) != nil else { continue }
            guard let name = displayName(record) else { continue }
            let key = normalize(name) + "\u{0}" + ident
            guard !seen.contains(key) else { continue }
            seen.append(key)
            routes.append(MirrorRoute(name: name, identifier: ident, selected: isOn(record.value)))
        }
        return routes
    }

    public static func displayName(_ record: AXRecord) -> String? {
        if let title = meaningful(record.title) { return title }
        if let description = meaningful(record.description) { return description }
        if let value = meaningful(record.value), !isStateToken(value) { return value }
        return nameFromIdentifier(record.identifier)
    }

    public static func labels(_ records: [AXRecord]) -> [String] {
        var names: [String] = []
        for record in records {
            let name = displayName(record) ?? record.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, meaningful(name) != nil || !record.identifier.isEmpty, !names.contains(name) else { continue }
            if meaningful(name) == nil, record.identifier.isEmpty { continue }
            if !names.contains(name) { names.append(name) }
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
        if lowered.contains("-1743") || lowered.contains("-25211") || lowered.contains("-10006") { return true }
        if lowered.contains("not authorized") { return true }
        if lowered.contains("not allowed assistive") { return true }
        if lowered.contains("assistive access") { return true }
        return false
    }

    public static func notReadyProblem(_ detail: String) -> Bool {
        if syntaxProblem(detail) || permissionProblem(detail) { return false }
        let lowered = detail.lowercased()
        return lowered.contains("-1719") || lowered.contains("invalid index")
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
        if notReadyProblem(detail) {
            return HomeSignalError.notReady(detail)
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

    public static func meaningful(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folded = normalize(trimmed)
        let generic: Set<String> = [
            "toggle button", "button", "checkbox", "check box", "radio button", "radio",
            "menu button", "pop up button", "group", "missing", "missing value", "image", "text", "static text",
        ]
        guard !generic.contains(folded) else { return nil }
        return trimmed
    }

    public static func nameFromIdentifier(_ identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.lowercased()
        let modulePrefix = "screen-mirroring-"
        if folded.isEmpty || folded == screenMirroringModuleID || folded.hasSuffix("-header") || !folded.hasPrefix(modulePrefix) {
            return nil
        }
        let rest = String(trimmed.dropFirst(modulePrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.isEmpty || normalize(rest) == "header" || isOpaqueRouteToken(rest) { return nil }
        if let dash = rest.firstIndex(of: "-") {
            let kind = rest[..<dash]
            let name = rest[rest.index(after: dash)...].trimmingCharacters(in: .whitespacesAndNewlines)
            let kindIsSlug = !kind.isEmpty && kind.unicodeScalars.allSatisfy { scalar in
                (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57)
            }
            if kindIsSlug {
                if name.isEmpty || normalize(name) == "header" || isOpaqueRouteToken(name) { return nil }
                return String(name)
            }
        }
        return rest
    }

    public static func isOpaqueRouteToken(_ raw: String) -> Bool {
        let text = normalize(raw)
        if text == "preferences" || text == "screen-mirroring-preferences" { return true }
        if text.hasPrefix("airplay:") || text.hasPrefix("screen-mirroring-device-airplay:") { return true }
        return text.range(
            of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
            options: .regularExpression
        ) != nil
    }

    public static func routeName(_ raw: String) -> String? {
        guard let text = meaningful(raw) else { return nil }
        if isStateToken(text) || isOpaqueRouteToken(text) || isScreenMirroringLabel(text) { return nil }
        if normalize(text) == "preferences" { return nil }
        return text
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
        let text = normalize(value)
        return text == "1" || text == "true" || text == "on" || text == "yes"
    }

    private static func isStateToken(_ value: String) -> Bool {
        let text = normalize(value)
        return text == "0" || text == "1" || text == "true" || text == "false" || text == "on" || text == "off" || text == "yes" || text == "no" || text == "missing value"
    }

    public static func deviceRoutes(in root: AXElement) -> DeviceListRead {
        guard let list = find(root, identifier: deviceListID) else {
            return DeviceListRead(routes: [], checkboxCount: 0, unnamed: [])
        }
        let boxes = checkboxes(in: list)
        let labels = visibleLabels(in: list)
        var routes: [MirrorRoute] = []
        var unnamed: [String] = []
        for (index, box) in boxes.enumerated() {
            let ident = box.attribute("AXIdentifier").trimmingCharacters(in: .whitespacesAndNewlines)
            var name = name(on: box)
            if name == nil, labels.count == boxes.count {
                name = labels[index]
            }
            if name == nil {
                name = nameFromIdentifier(ident)
            }
            if let name {
                routes.append(MirrorRoute(name: name, identifier: ident, selected: isOn(box.attribute("AXValue"))))
            } else {
                unnamed.append("row \(index + 1) id=\(ident.isEmpty ? "(none)" : ident)")
            }
        }
        return DeviceListRead(routes: routes, checkboxCount: boxes.count, unnamed: unnamed)
    }

    public static func screenMirroringIdentifiers(in element: AXElement) -> [String] {
        var found: [String] = []
        func walk(_ node: AXElement) {
            let ident = node.attribute("AXIdentifier").trimmingCharacters(in: .whitespacesAndNewlines)
            if ident.lowercased().contains("screen-mirroring"), !found.contains(ident) {
                found.append(ident)
            }
            for child in node.children {
                walk(child)
            }
        }
        walk(element)
        return found
    }

    public static func formatAttributes(_ element: AXElement, depth: Int = 0) -> String {
        var lines: [String] = []
        writeAttributes(element, depth: depth, into: &lines)
        return lines.joined(separator: "\n")
    }

    private static func find(_ element: AXElement, identifier: String) -> AXElement? {
        if element.attribute("AXIdentifier").caseInsensitiveCompare(identifier) == .orderedSame {
            return element
        }
        for child in element.children {
            if let found = find(child, identifier: identifier) {
                return found
            }
        }
        return nil
    }

    private static func checkboxes(in element: AXElement) -> [AXElement] {
        var found: [AXElement] = []
        func walk(_ node: AXElement) {
            if isCheckbox(node) {
                found.append(node)
            }
            for child in node.children {
                walk(child)
            }
        }
        for child in element.children {
            walk(child)
        }
        return found
    }

    private static func visibleLabels(in list: AXElement) -> [String] {
        var labels: [String] = []
        func walk(_ node: AXElement) {
            if isCheckbox(node) { return }
            let ident = node.attribute("AXIdentifier").lowercased()
            if ident.hasSuffix("-header") || ident.hasSuffix("-preferences") { return }
            if isTextRole(node.role), let text = textAttributes(node) {
                labels.append(text)
            }
            for child in node.children {
                walk(child)
            }
        }
        for child in list.children {
            walk(child)
        }
        return labels
    }

    private static func name(on element: AXElement) -> String? {
        if let own = textAttributes(element) { return own }
        for child in element.children where !isCheckbox(child) {
            if let found = name(on: child) { return found }
        }
        return nil
    }

    private static func textAttributes(_ element: AXElement) -> String? {
        let keys = ["AXTitle", "AXLabel", "AXAttributedDescription", "AXHelp", "AXCustomContent", "AXDescription", "AXValue"]
        for key in keys {
            let raw = element.attribute(key)
            if key == "AXCustomContent" {
                if let name = customContentName(raw) { return name }
                continue
            }
            if let name = routeName(raw) { return name }
        }
        return nil
    }

    private static func customContentName(_ raw: String) -> String? {
        var values: [String] = []
        var labels: [String] = []
        for piece in raw.split(separator: ";") {
            let parts = piece.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                if normalize(parts[0]) == "value" { values.append(parts[1]) }
                else { labels.append(parts[1]) }
            } else if let only = parts.first, !only.isEmpty {
                values.append(only)
            }
        }
        for candidate in values + labels {
            if let name = routeName(candidate) { return name }
        }
        return nil
    }

    private static func isCheckbox(_ element: AXElement) -> Bool {
        let role = (element.role + " " + element.attribute("AXRole")).lowercased()
        return role.contains("checkbox") || role.contains("check box")
    }

    private static func isTextRole(_ role: String) -> Bool {
        let text = role.lowercased()
        return text.contains("statictext") || text.contains("static text") || text == "axtext" || text == "text"
    }

    private static func writeAttributes(_ element: AXElement, depth: Int, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)\(element.role.isEmpty ? "AXUnknown" : element.role)")
        let keys = element.attributes.keys.sorted { lhs, rhs in
            let left = attributeRank(lhs)
            let right = attributeRank(rhs)
            if left != right { return left < right }
            return lhs < rhs
        }
        for key in keys {
            lines.append("\(indent)  \(key)=\(element.attributes[key] ?? "")")
        }
        for child in element.children {
            writeAttributes(child, depth: depth + 1, into: &lines)
        }
    }

    private static func attributeRank(_ key: String) -> Int {
        let order = [
            "AXRole", "AXSubrole", "AXIdentifier", "AXTitle", "AXDescription", "AXValue",
            "AXLabel", "AXHelp", "AXAttributedDescription", "AXCustomContent",
        ]
        return order.firstIndex(of: key) ?? order.count
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
