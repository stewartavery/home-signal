import Foundation
import HomeSignalCore

public actor SimulatedCapture: CaptureChannel {
    public init() {}

    public func capture(display: String, displays: [DisplayBounds], to path: String?, dryRun: Bool) async throws -> CaptureResult {
        let bounds = try DisplayGeometry.displayBounds(named: display, in: displays)
        let output = path ?? HomeSignalPaths.expand("~/.local/share/home-signal/screenshots/\(bounds.name).txt")
        if !dryRun {
            let parent = (output as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try Data("home-signal simulated capture\n".utf8).write(to: URL(fileURLWithPath: output))
        }
        return CaptureResult(path: output, display: bounds.name, width: bounds.width, height: bounds.height)
    }
}

#if os(macOS)
import AppKit
import ScreenCaptureKit

public struct ScreenCaptureChannel: CaptureChannel {
    public init() {}

    public func capture(display: String, displays: [DisplayBounds], to path: String?, dryRun: Bool) async throws -> CaptureResult {
        let bounds = try DisplayGeometry.displayBounds(named: display, in: displays)
        let output = path ?? defaultPath(display: bounds.name)
        if dryRun {
            return CaptureResult(path: output, display: bounds.name, width: bounds.width, height: bounds.height)
        }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw HomeSignalError.unsupported(
                "Screen capture failed: \(error)",
                hint: "Grant Screen Recording permission to the agent."
            )
        }
        guard let screen = content.displays.first(where: { candidate in
            abs(candidate.width - bounds.width) <= 2 && abs(candidate.height - bounds.height) <= 2
        }) ?? content.displays.first else {
            throw HomeSignalError.notFound("display", name: display)
        }
        let filter = SCContentFilter(display: screen, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = screen.width
        configuration.height = screen.height
        configuration.showsCursor = false
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw HomeSignalError.unsupported(
                "Screen capture failed: \(error)",
                hint: "Grant Screen Recording permission to the agent."
            )
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw HomeSignalError.backend("Could not encode the screenshot as PNG.")
        }
        let parent = (output as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: output))
        return CaptureResult(path: output, display: bounds.name, width: image.width, height: image.height)
    }

    private func defaultPath(display: String) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safe = display.replacingOccurrences(of: " ", with: "-")
        return HomeSignalPaths.expand("~/.local/share/home-signal/screenshots/\(stamp)-\(safe).png")
    }
}
#endif
