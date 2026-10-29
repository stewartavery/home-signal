import XCTest

#if os(macOS)
import AppKit
import SnapshotTesting
import WebKit
@testable import HomeSignalCore

@MainActor
final class DisplayProofMacSmokeTests: XCTestCase {
    private var retained: (NSWindow, WKWebView, NSObject)?

    func testMessageDefault() throws {
        try smoke(name: "message-default")
    }

    func testScheduleMoonlit() throws {
        try smoke(name: "schedule-moonlit")
    }

    func testOverflowMessage() throws {
        try smoke(name: "overflow-message")
    }

    private func smoke(name: String) throws {
        let mode = ProcessInfo.processInfo.environment["HS_MAC_PROOF"]
        guard mode == "1" || mode == "record" else {
            throw XCTSkip("Set HS_MAC_PROOF=1 to compare darwin baselines, or HS_MAC_PROOF=record to write them.")
        }
        let html = try String(contentsOf: repoRoot().appendingPathComponent("Fixtures/DisplayProof/\(name).html"), encoding: .utf8)
        let image = try snapshot(html: html)
        let directory = repoRoot().appendingPathComponent("Fixtures/DisplayProof/screenshots/darwin")
        let failure = verifySnapshot(
            of: image,
            as: .image,
            named: "mac",
            record: mode == "record" ? .all : .never,
            snapshotDirectory: directory.path,
            testName: name
        )
        if let failure {
            XCTFail(failure)
        }
    }

    private func snapshot(html: String) throws -> NSImage {
        let frame = NSRect(x: 0, y: 0, width: CGFloat(DisplayProof.stageWidth), height: CGFloat(DisplayProof.stageHeight))
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let webView = WKWebView(frame: frame)
        window.contentView = webView
        window.setContentSize(NSSize(width: frame.width, height: frame.height))
        let delegate = LoadDelegate()
        webView.navigationDelegate = delegate
        retained = (window, webView, delegate)
        let loaded = expectation(description: "load")
        var loadError: Error?
        delegate.onFinish = { loaded.fulfill() }
        delegate.onFail = { error in
            loadError = error
            loaded.fulfill()
        }
        webView.loadHTMLString(html, baseURL: nil)
        window.orderFrontRegardless()
        wait(for: [loaded], timeout: 15)
        if let loadError { throw loadError }
        let ready = expectation(description: "ready")
        pollReady(webView, remaining: 100, expectation: ready)
        wait(for: [ready], timeout: 15)
        let shot = expectation(description: "snapshot")
        var image: NSImage?
        var shotError: Error?
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = false
        webView.takeSnapshot(with: config) { result, error in
            image = result
            shotError = error
            shot.fulfill()
        }
        wait(for: [shot], timeout: 15)
        if let shotError { throw shotError }
        guard let image else {
            throw HomeSignalError.backend("WKWebView snapshot was empty.")
        }
        return image
    }

    private func pollReady(_ webView: WKWebView, remaining: Int, expectation: XCTestExpectation) {
        webView.evaluateJavaScript("document.fonts.status === 'loaded' && document.documentElement.getAttribute('data-hs-ready') === '1'") { value, _ in
            if (value as? Bool) == true || remaining <= 0 {
                expectation.fulfill()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.pollReady(webView, remaining: remaining - 1, expectation: expectation)
                }
            }
        }
    }

    private func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        let manager = FileManager.default
        while url.path != "/" {
            if manager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: manager.currentDirectoryPath)
    }

    private final class LoadDelegate: NSObject, WKNavigationDelegate {
        var onFinish: (() -> Void)?
        var onFail: ((Error) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinish?()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFail?(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onFail?(error)
        }
    }
}
#else
final class DisplayProofMacSmokeTests: XCTestCase {
    func testSkippedOnThisPlatform() throws {
        throw XCTSkip("WKWebView display proof smoke runs on macOS only.")
    }
}
#endif
