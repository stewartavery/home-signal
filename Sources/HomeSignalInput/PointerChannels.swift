import HomeSignalCore

public actor SimulatedPointer: InputChannel {
    public private(set) var events: [String] = []
    public init() {}

    public func click(at point: Point, button: String, clicks: Int, dryRun: Bool) async -> Point {
        if !dryRun { events.append("click \(button) \(clicks) \(point.x),\(point.y)") }
        return point
    }

    public func move(to point: Point, dryRun: Bool) async -> Point {
        if !dryRun { events.append("move \(point.x),\(point.y)") }
        return point
    }

    public func scroll(at point: Point, delta: Int, axis: String, dryRun: Bool) async -> Point {
        if !dryRun { events.append("scroll \(axis) \(delta) \(point.x),\(point.y)") }
        return point
    }

    public func park(displays: [DisplayBounds], display: String, corner: String, inset: Int, dryRun: Bool) async throws -> Point {
        let point = try DisplayGeometry.park(displays: displays, display: display, corner: corner, inset: inset)
        if !dryRun { events.append("park \(point.x),\(point.y)") }
        return point
    }
}

#if os(macOS)
import CoreGraphics
import Darwin

public struct CGEventPointer: InputChannel {
    public init() {}

    public func click(at point: Point, button: String, clicks: Int, dryRun: Bool) async throws -> Point {
        try validate(button: button, clicks: clicks)
        if dryRun { return point }
        let mouseButton: CGMouseButton = button == "right" ? .right : .left
        let down: CGEventType = mouseButton == .right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = mouseButton == .right ? .rightMouseUp : .leftMouseUp
        let repeats = max(clicks, 1)
        for index in 1...repeats {
            try post(point, type: down, button: mouseButton, clickState: index)
            usleep(80_000)
            try post(point, type: up, button: mouseButton, clickState: index)
            usleep(80_000)
        }
        return point
    }

    public func move(to point: Point, dryRun: Bool) async throws -> Point {
        if dryRun { return point }
        try post(point, type: .mouseMoved, button: .left, clickState: 0)
        return point
    }

    public func scroll(at point: Point, delta: Int, axis: String, dryRun: Bool) async throws -> Point {
        guard axis == "vertical" || axis == "horizontal" else {
            throw HomeSignalError.usage("Scroll axis must be vertical or horizontal.")
        }
        if dryRun { return point }
        try post(point, type: .mouseMoved, button: .left, clickState: 0)
        let vertical: Int32 = axis == "vertical" ? Int32(delta) : 0
        let horizontal: Int32 = axis == "horizontal" ? Int32(delta) : 0
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ) else {
            throw HomeSignalError.unsupported("Could not create a scroll event.", hint: "Grant Accessibility permission to the agent.")
        }
        event.post(tap: .cghidEventTap)
        return point
    }

    public func park(displays: [DisplayBounds], display: String, corner: String, inset: Int, dryRun: Bool) async throws -> Point {
        let point = try DisplayGeometry.park(displays: displays, display: display, corner: corner, inset: inset)
        return try await move(to: point, dryRun: dryRun)
    }

    private func validate(button: String, clicks: Int) throws {
        guard button == "left" || button == "right" else {
            throw HomeSignalError.usage("Button must be left or right.")
        }
        guard (1...3).contains(clicks) else {
            throw HomeSignalError.usage("Clicks must be from 1 to 3.")
        }
    }

    private func post(_ point: Point, type: CGEventType, button: CGMouseButton, clickState: Int) throws {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: CGPoint(x: point.x, y: point.y),
            mouseButton: button
        ) else {
            throw HomeSignalError.unsupported("Could not create a pointer event.", hint: "Grant Accessibility permission to the agent.")
        }
        if clickState > 0 {
            event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        }
        event.post(tap: .cghidEventTap)
    }
}
#endif
