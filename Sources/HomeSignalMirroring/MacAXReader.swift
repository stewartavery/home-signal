#if os(macOS)
import AppKit
import ApplicationServices
import HomeSignalCore

public struct MacScreenMirroringReader: ScreenMirroringReading {
    public init() {}

    public func snapshot() async throws -> AXElement {
        let pid = await MainActor.run { Self.controlCenterPID() }
        guard let pid else {
            return AXElement(role: "AXApplication", attributes: [:], children: [])
        }
        return try Self.read(pid: pid)
    }

    // Receiver rows sit under the Control Center window, a scroll area, and
    // screen-mirroring-device-list. Their names may be child elements. A walk
    // that stops at depth 6 never leaves the preferences button. The cap below
    // only breaks cycles.
    private static let maxDepth = 64
    private static let maxNodes = 8000

    @MainActor
    private static func controlCenterPID() -> pid_t? {
        controlCenterApplication()?.processIdentifier
    }

    private static func read(pid: pid_t) throws -> AXElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Float(1.5))
        var nodes = 0
        var windowsValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowsValue)
        if error == .apiDisabled || error == .notImplemented {
            throw HomeSignalError.permissionDenied("Accessibility is not granted to this process (AXError \(error.rawValue)).")
        }
        let windows = windowsValue.map { elements(from: $0) } ?? []
        if windows.isEmpty {
            return try readElement(application, depth: 0, nodes: &nodes)
        }
        var read: [AXElement] = []
        for window in windows {
            read.append(try readElement(window, depth: 0, nodes: &nodes))
        }
        if let titled = read.first(where: { MirrorAX.normalize($0.attribute("AXTitle")) == "control center" }) {
            return titled
        }
        if let dialog = read.first(where: { $0.attribute("AXSubrole") == "AXSystemDialog" }) {
            return dialog
        }
        return read[0]
    }

    @MainActor
    private static func controlCenterApplication() -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications
        return running.first { $0.bundleIdentifier == "com.apple.controlcenter" }
            ?? running.first { $0.localizedName == "Control Center" }
            ?? running.first { $0.executableURL?.lastPathComponent == "ControlCenter" }
    }

    private static func readElement(_ element: AXUIElement, depth: Int, nodes: inout Int) throws -> AXElement {
        nodes += 1
        if depth > maxDepth || nodes > maxNodes {
            return AXElement(role: "AXUnknown", attributes: [:], children: [])
        }
        var namesRef: CFArray?
        let nameError = AXUIElementCopyAttributeNames(element, &namesRef)
        if nameError == .apiDisabled || nameError == .notImplemented {
            throw HomeSignalError.permissionDenied("Accessibility is not granted to this process (AXError \(nameError.rawValue)).")
        }
        let names = (namesRef as? [String]) ?? []
        var attributes: [String: String] = [:]
        for name in names where !isStructural(name) {
            if let raw = copy(element, name), let text = stringify(raw) {
                attributes[name] = text
            } else {
                attributes[name] = ""
            }
        }
        let role = attributes["AXRole"] ?? ""
        var children: [AXElement] = []
        for child in childElements(element) {
            children.append(try readElement(child, depth: depth + 1, nodes: &nodes))
        }
        return AXElement(role: role.isEmpty ? "AXUnknown" : role, attributes: attributes, children: children)
    }

    private static func isStructural(_ name: String) -> Bool {
        name == (kAXChildrenAttribute as String) || name == "AXVisibleChildren" || name == (kAXWindowsAttribute as String)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    private static func childElements(_ element: AXUIElement) -> [AXUIElement] {
        var collected: [AXUIElement] = []
        for attribute in [kAXChildrenAttribute as String, "AXVisibleChildren"] {
            guard let raw = copy(element, attribute) else { continue }
            for child in elements(from: raw) where !collected.contains(where: { CFEqual($0 as CFTypeRef, child as CFTypeRef) }) {
                collected.append(child)
            }
        }
        return collected
    }

    private static func elements(from value: CFTypeRef) -> [AXUIElement] {
        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return [value as! AXUIElement]
        }
        guard let array = value as? NSArray else { return [] }
        var result: [AXUIElement] = []
        for index in 0..<array.count {
            let item = array.object(at: index) as AnyObject
            if CFGetTypeID(item) == AXUIElementGetTypeID() {
                result.append(item as! AXUIElement)
            }
        }
        return result
    }

    private static func stringify(_ value: CFTypeRef) -> String? {
        if CFGetTypeID(value) == AXUIElementGetTypeID() { return nil }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        if let attributed = value as? NSAttributedString { return attributed.string }
        guard let array = value as? NSArray else {
            return nil
        }
        if array.count == 0 { return "" }
        var parts: [String] = []
        var structural = true
        for index in 0..<array.count {
            let item = array.object(at: index)
            if let object = item as? NSObject, CFGetTypeID(object) == AXUIElementGetTypeID() {
                continue
            }
            structural = false
            if let text = item as? String {
                parts.append(text)
            } else if let text = customText(item) {
                parts.append(text)
            }
        }
        if structural { return nil }
        return parts.joined(separator: "; ")
    }

    private static func customText(_ item: Any) -> String? {
        guard let object = item as? NSObject else { return nil }
        var label = ""
        var value = ""
        for key in ["label", "value"] {
            guard object.responds(to: NSSelectorFromString(key)) else { continue }
            let raw = object.value(forKey: key)
            let text: String
            if let string = raw as? String {
                text = string
            } else if let attributed = raw as? NSAttributedString {
                text = attributed.string
            } else {
                text = ""
            }
            if key == "label" { label = text } else { value = text }
        }
        if label.isEmpty && value.isEmpty { return nil }
        if label.isEmpty { return value }
        if value.isEmpty { return label }
        return "label=\(label); value=\(value)"
    }
}
#endif
