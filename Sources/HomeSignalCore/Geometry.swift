public struct CocoaFrame: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum ClickSpec: Sendable, Equatable {
    case absolute(Point)
    case panelFraction(x: Double, y: Double)
    case displayFraction(display: String, x: Double, y: Double)
}

public enum DisplayGeometry {
    /// Cocoa screen frames use a bottom-left origin. CGEvent and System Events use a top-left origin on the primary display, with y increasing downward.
    public static func fromCocoaFrames(_ frames: [CocoaFrame]) -> [DisplayBounds] {
        guard let primary = frames.first(where: { abs($0.x) < 0.5 && abs($0.y) < 0.5 }) ?? frames.first else {
            return []
        }
        var secondaryAssigned = false
        return frames.enumerated().map { index, frame in
            let isPrimary = abs(frame.x) < 0.5 && abs(frame.y) < 0.5
            let originX = Int(frame.x.rounded())
            let originY = Int((primary.height - (frame.y + frame.height)).rounded())
            let name: String
            if isPrimary {
                name = "main"
            } else if !secondaryAssigned {
                name = "secondary"
                secondaryAssigned = true
            } else {
                name = "display-\(index + 1)"
            }
            return DisplayBounds(
                name: name,
                width: Int(frame.width.rounded()),
                height: Int(frame.height.rounded()),
                originX: originX,
                originY: originY,
                primary: isPrimary
            )
        }
    }

    public static func applyingNames(probed: [DisplayBounds], configured: [DisplayBounds]) -> [DisplayBounds] {
        probed.map { probe in
            guard let match = configured.first(where: {
                abs($0.originX - probe.originX) <= 2 && abs($0.originY - probe.originY) <= 2
            }) else {
                return probe
            }
            return DisplayBounds(
                name: match.name,
                width: probe.width,
                height: probe.height,
                originX: probe.originX,
                originY: probe.originY,
                primary: probe.primary,
                deviceID: probe.deviceID
            )
        }
    }

    public static func resolve(_ spec: ClickSpec, panel: PanelBounds?, displays: [DisplayBounds]) throws -> Point {
        switch spec {
        case .absolute(let point):
            return point
        case .panelFraction(let x, let y):
            guard let panel else {
                throw HomeSignalError.backend(
                    "The Screen Mirroring panel bounds were not available.",
                    hint: "Open Control Center once so the agent can read the panel, or set absolute points under [mirror.absolute]."
                )
            }
            return Point(x: panel.x + panel.width * x, y: panel.y + panel.height * y)
        case .displayFraction(let display, let x, let y):
            let bounds = try displayBounds(named: display, in: displays)
            return Point(
                x: Double(bounds.originX) + Double(bounds.width) * x,
                y: Double(bounds.originY) + Double(bounds.height) * y
            )
        }
    }

    public static func park(displays: [DisplayBounds], display: String, corner: String, inset: Int) throws -> Point {
        let bounds = try displayBounds(named: display, in: displays)
        let margin = Double(inset)
        let left = Double(bounds.originX) + margin
        let right = Double(bounds.originX + bounds.width) - margin
        let top = Double(bounds.originY) + margin
        let bottom = Double(bounds.originY + bounds.height) - margin
        switch corner {
        case "bottom-right":
            return Point(x: right, y: bottom)
        case "bottom-left":
            return Point(x: left, y: bottom)
        case "top-right":
            return Point(x: right, y: top)
        case "top-left":
            return Point(x: left, y: top)
        default:
            throw HomeSignalError.usage("Corner must be bottom-right, bottom-left, top-right, or top-left.")
        }
    }

    public static func displayBounds(named name: String, in displays: [DisplayBounds]) throws -> DisplayBounds {
        if let match = displays.first(where: { $0.name == name }) {
            return match
        }
        if let index = Int(name), index > 0, index <= displays.count {
            return displays[index - 1]
        }
        throw HomeSignalError.notFound("display", name: name)
    }
}
