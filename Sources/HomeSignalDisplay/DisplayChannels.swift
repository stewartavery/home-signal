import HomeSignalCore

public actor SimulatedDisplay: DisplayChannel {
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

    public func show(html: String, kind: String, present: Bool, screenName: String?, displays: [DisplayBounds]) async throws -> DisplayReadback {
        ensureWindow(named: screenName, displays: displays)
        guard let webView else {
            throw HomeSignalError.backend("The signal window has no view.")
        }
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
        if present {
            window?.orderFrontRegardless()
        }
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

    private func ensureWindow(named screenName: String?, displays: [DisplayBounds]) {
        let screen = pickScreen(named: screenName, displays: displays) ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
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

    private func pickScreen(named screenName: String?, displays: [DisplayBounds]) -> NSScreen? {
        guard let screenName, let bounds = displays.first(where: { $0.name == screenName }) else {
            return NSScreen.main
        }
        return NSScreen.screens.first { screen in
            abs(Int(screen.frame.width.rounded()) - bounds.width) <= 2
                && abs(Int(screen.frame.height.rounded()) - bounds.height) <= 2
        }
    }
}

public final class MacDisplayChannel: DisplayChannel, @unchecked Sendable {
    private let screenName: String
    private let displays: @Sendable () -> [DisplayBounds]

    public init(screenName: String, displays: @escaping @Sendable () -> [DisplayBounds]) {
        self.screenName = screenName
        self.displays = displays
    }

    public func show(html: String, kind: String, present: Bool) async throws -> DisplayReadback {
        let name = screenName
        let screens = displays()
        return try await MacDisplayWindow.shared.show(html: html, kind: kind, present: present, screenName: name, displays: screens)
    }

    public func readback() async -> DisplayReadback? {
        await MacDisplayWindow.shared.current()
    }

    public func clear(present: Bool) async {
        await MacDisplayWindow.shared.clear(present: present)
    }
}
#endif
