import HomeSignalCore

public actor SimulatedDisplay: DisplayChannel, DisplayPlacing {
    private var shownHTML: String?
    private var shown: DisplayReadback?

    public init() {}

    public func show(html: String, kind: String, present: Bool) async throws -> DisplayReadback {
        _ = present
        shownHTML = html
        let readback = DisplayReadback(contentHash: ContentHash.sha256(html), title: DisplayTitle.parse(html), kind: kind)
        shown = readback
        return readback
    }

    public func readback() async -> DisplayReadback? {
        shown
    }

    public func clear(present: Bool) async {
        _ = present
        shownHTML = nil
        shown = nil
    }

    public func presentedHTML() async -> String? {
        shownHTML
    }

    public func place(html: String, kind: String, present: Bool, target: DisplayTarget) async throws -> PlacementReport {
        let readback = try await show(html: html, kind: kind, present: present)
        return PlacementReport(readback: readback, screenName: target.name, deviceID: target.deviceID, fullScreen: true)
    }

    public func dismiss() async {
        await clear(present: true)
    }
}

#if os(macOS)
import AppKit
import WebKit

@MainActor
public final class MacDisplayWindow: NSObject, WKNavigationDelegate {
    public static let shared = MacDisplayWindow()
    private var window: NSWindow?
    private var webView: WKWebView?
    private var loadedHTML: String?
    private var readback: DisplayReadback?
    private var loadWaiter: CheckedContinuation<Void, Never>?
    private var loadFinished = false

    public func place(html: String, kind: String, present: Bool, target: DisplayTarget) async throws -> PlacementReport {
        let screen = try screen(for: target)
        ensureWindow(on: screen)
        guard let webView else {
            throw HomeSignalError.displayStep("place", "The signal window has no view.")
        }
        let readback = try await load(html: html, kind: kind, into: webView)
        guard let window else {
            throw HomeSignalError.displayStep("place", "The signal window was not created.")
        }
        guard let placed = window.screen else {
            window.orderOut(nil)
            throw HomeSignalError.displayStep("place", "The window is not on a screen. Refusing to use another screen.")
        }
        let placedID = ScreenIdentity.deviceID(placed)
        let placedName = placed.localizedName
        let fullScreen = covers(screen)
        let onScreen = ScreenIdentity.matches(placed, target: target)
        guard onScreen, fullScreen else {
            window.orderOut(nil)
            if !onScreen {
                throw HomeSignalError.displayStep(
                    "place",
                    "The window is on \(placedName), not \(target.name). Refusing to use another screen."
                )
            }
            throw HomeSignalError.displayStep("place", "The window does not cover \(target.name).")
        }
        if present {
            window.orderFrontRegardless()
        }
        return PlacementReport(
            readback: readback,
            screenName: placedName,
            deviceID: placedID,
            fullScreen: true
        )
    }

    private func load(html: String, kind: String, into webView: WKWebView) async throws -> DisplayReadback {
        loadFinished = false
        webView.loadHTMLString(html, baseURL: nil)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if loadFinished {
                continuation.resume()
            } else {
                loadWaiter = continuation
            }
        }
        let domTitle = try await title(in: webView)
        let parsed = DisplayTitle.parse(html)
        let normalized = domTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let dom = (normalized?.isEmpty == false) ? normalized : nil
        if dom != parsed {
            throw HomeSignalError.displayMismatch(
                expected: DisplayReadback(contentHash: ContentHash.sha256(html), title: parsed, kind: kind),
                actual: DisplayReadback(contentHash: ContentHash.sha256(html), title: dom, kind: kind)
            )
        }
        loadedHTML = html
        window?.title = parsed ?? ""
        let value = DisplayReadback(contentHash: ContentHash.sha256(html), title: parsed, kind: kind)
        readback = value
        return value
    }

    public func current() -> DisplayReadback? {
        readback
    }

    public func clear(present: Bool) {
        loadedHTML = nil
        readback = nil
        if present {
            window?.orderOut(nil)
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadFinished = true
        loadWaiter?.resume()
        loadWaiter = nil
    }

    private func title(in webView: WKWebView) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("document.title") { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? String)
                }
            }
        }
    }

    // Borderless signal windows cover the target screen's frame. toggleFullScreen would restyle the window and animate.
    private func ensureWindow(on screen: NSScreen) {
        let frame = screen.frame
        if window == nil {
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.hasShadow = false
            window.isOpaque = true
            let webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size))
            webView.navigationDelegate = self
            window.contentView = webView
            self.window = window
            self.webView = webView
        }
        window?.setFrame(frame, display: true)
    }

    private func screen(for target: DisplayTarget) throws -> NSScreen {
        if let match = NSScreen.screens.first(where: { ScreenIdentity.matches($0, target: target) }) {
            return match
        }
        let attached = NSScreen.screens.map { $0.localizedName }
        let listed = attached.isEmpty ? "none" : attached.joined(separator: ", ")
        throw HomeSignalError.displayStep(
            "place",
            "Target display \(target.name) is not attached (\(listed)). Refusing to use another screen."
        )
    }

    private func covers(_ screen: NSScreen) -> Bool {
        guard let frame = window?.frame else { return false }
        let target = screen.frame
        return abs(frame.origin.x - target.origin.x) <= 2
            && abs(frame.origin.y - target.origin.y) <= 2
            && abs(frame.size.width - target.size.width) <= 2
            && abs(frame.size.height - target.size.height) <= 2
    }
}

@MainActor
enum ScreenIdentity {
    static func deviceID(_ screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return "" }
        return number.stringValue
    }

    static func matches(_ screen: NSScreen, target: DisplayTarget) -> Bool {
        if !target.deviceID.isEmpty, deviceID(screen) == target.deviceID {
            return true
        }
        return screen.localizedName == target.name
    }
}

public struct MacAttachedDisplays: AttachedDisplayListing {
    public init() {}

    public func attachedDisplays() async -> [AttachedDisplay] {
        await MainActor.run {
            let screens = NSScreen.screens
            let frames = screens.map { screen in
                CocoaFrame(
                    x: screen.frame.origin.x,
                    y: screen.frame.origin.y,
                    width: screen.frame.width,
                    height: screen.frame.height
                )
            }
            return zip(screens, DisplayGeometry.fromCocoaFrames(frames)).map { screen, bounds in
                AttachedDisplay(
                    name: screen.localizedName,
                    deviceID: ScreenIdentity.deviceID(screen),
                    width: bounds.width,
                    height: bounds.height,
                    originX: bounds.originX,
                    originY: bounds.originY,
                    primary: bounds.primary
                )
            }
        }
    }
}

public final class MacDisplayChannel: DisplayChannel, DisplayPlacing, @unchecked Sendable {
    public init() {}

    public func show(html: String, kind: String, present: Bool) async throws -> DisplayReadback {
        _ = (html, kind, present)
        throw HomeSignalError.displayStep("place", "Refusing to show without the target display. The window is not moved to another screen.")
    }

    public func place(html: String, kind: String, present: Bool, target: DisplayTarget) async throws -> PlacementReport {
        try await MacDisplayWindow.shared.place(html: html, kind: kind, present: present, target: target)
    }

    public func readback() async -> DisplayReadback? {
        await MacDisplayWindow.shared.current()
    }

    public func clear(present: Bool) async {
        await MacDisplayWindow.shared.clear(present: present)
    }

    public func dismiss() async {
        await clear(present: true)
    }
}
#endif
