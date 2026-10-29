import XCTest
@testable import HomeSignalCore

final class DisplayMediaTests: XCTestCase {
    func testRendersHTMLInAContainedSlot() throws {
        let fragment = "<p>Example notice</p><style>body{background:red}</style><script>example()</script>"
        let html = try renderModule(#"{"type":"html","html":"\#(fragment)"}"#)
        XCTAssertTrue(html.contains("data-module=\"html\""))
        XCTAssertTrue(html.contains("class=\"embed\""))
        XCTAssertTrue(html.contains("flex:1"))
        XCTAssertTrue(html.contains("srcdoc=\"\(DisplayRendering.escape(fragment))\""))
        XCTAssertFalse(html.contains("<script>example()</script>"))
        XCTAssertFalse(html.contains("<style>body{background:red}</style>"))
        XCTAssertEqual(moduleCount(html), 1)
    }

    func testHTMLKeepsMarkupThatWouldCloseTheSlot() throws {
        let fragment = "</section><div>Example notice</div>"
        let html = try renderModule(#"{"type":"html","html":"\#(fragment)"}"#)
        XCTAssertTrue(html.contains("srcdoc=\"\(DisplayRendering.escape(fragment))\""))
        XCTAssertEqual(moduleCount(html), 1)
        XCTAssertTrue(html.contains("</iframe></section>"))
    }

    func testHTMLRejectsEmpty() {
        assertRefusal(#"{"title":"Example","modules":[{"type":"html","html":""}]}"#)
        assertRefusal(#"{"title":"Example","modules":[{"type":"html","html":"  "}]}"#)
        assertRefusal(#"{"title":"Example","modules":[{"type":"html"}]}"#)
        XCTAssertThrowsError(try DisplayPage(title: "Example", blocks: [.html(html: " \n")])) { error in
            XCTAssertEqual((error as? HomeSignalError)?.exitCode, 1)
        }
    }

    func testRendersImageURLAndCaption() throws {
        let html = try renderModule(
            #"{"type":"image","src":"https://example.com/example.png?a=1&b=2","caption":"Fish & Chips"}"#
        )
        XCTAssertTrue(html.contains("data-module=\"image\""))
        XCTAssertTrue(html.contains("data-fit=\"contain\""))
        XCTAssertTrue(html.contains("object-fit:contain"))
        XCTAssertTrue(html.contains("src=\"https://example.com/example.png?a=1&amp;b=2\""))
        XCTAssertTrue(html.contains("alt=\"Fish &amp; Chips\""))
        XCTAssertTrue(html.contains("<p class=\"caption\">Fish &amp; Chips</p>"))
        XCTAssertTrue(html.contains("class=\"media-slot\""))
        XCTAssertFalse(html.contains("data:"))
    }

    func testImageCoverFit() throws {
        let html = try renderModule(
            #"{"type":"image","src":"https://example.com/example.png","fit":"cover"}"#
        )
        XCTAssertTrue(html.contains("data-fit=\"cover\""))
        XCTAssertTrue(html.contains(".media[data-fit=\"cover\"]{object-fit:cover}"))
        XCTAssertFalse(html.contains("class=\"caption\""))
    }

    func testImageEmbedsALocalFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hs-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("example.png")
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        try bytes.write(to: file)
        let html = try DisplayLayout.render(
            json: #"{"title":"Example","modules":[{"type":"image","src":"example.png","caption":"Example"}]}"#,
            baseDirectory: directory.path
        )
        XCTAssertTrue(html.contains("src=\"data:image/png;base64,\(bytes.base64EncodedString())\""))
        XCTAssertTrue(html.contains("Example"))
    }

    func testImageRejectsEmptyOrMissingSource() {
        assertRefusal(#"{"title":"Example","modules":[{"type":"image","src":""}]}"#)
        assertRefusal(#"{"title":"Example","modules":[{"type":"image","src":"   "}]}"#)
        assertRefusal(#"{"title":"Example","modules":[{"type":"image"}]}"#)
        assertRefusal(#"{"title":"Example","modules":[{"type":"image","src":"https://example.com/example.png","fit":"tile"}]}"#)
        XCTAssertThrowsError(
            try DisplayLayout.render(json: #"{"title":"Example","modules":[{"type":"image","src":"/tmp/hs-missing-\#(UUID().uuidString).png"}]}"#)
        ) { error in
            let signal = error as? HomeSignalError
            XCTAssertEqual(signal?.exitCode, 1)
            XCTAssertTrue(signal?.message.contains("not found") == true)
            XCTAssertTrue(signal?.message.contains("Refusing to replace the screen.") == true)
        }
    }

    func testRendersVideoDefaults() throws {
        let html = try renderModule(#"{"type":"video","src":"https://example.com/example.mp4"}"#)
        XCTAssertTrue(html.contains("data-module=\"video\""))
        XCTAssertTrue(html.contains("<video "))
        XCTAssertTrue(html.contains("playsinline"))
        XCTAssertTrue(html.contains(" autoplay"))
        XCTAssertTrue(html.contains(" muted"))
        XCTAssertTrue(html.contains(" loop"))
        XCTAssertTrue(html.contains("data-fit=\"contain\""))
        XCTAssertTrue(html.contains("src=\"https://example.com/example.mp4\""))
        XCTAssertTrue(html.contains("flex:1"))
    }

    func testVideoOverridesAndCover() throws {
        let html = try renderModule(
            #"{"type":"video","src":"https://example.com/example.webm","fit":"COVER","autoplay":false,"muted":false,"loop":false,"caption":"Example"}"#
        )
        XCTAssertTrue(html.contains("data-fit=\"cover\""))
        XCTAssertTrue(html.contains("src=\"https://example.com/example.webm\""))
        XCTAssertTrue(html.contains("<p class=\"caption\">Example</p>"))
        XCTAssertFalse(html.contains(" autoplay"))
        XCTAssertFalse(html.contains(" muted"))
        XCTAssertFalse(html.contains(" loop"))
        XCTAssertTrue(html.contains("playsinline"))
    }

    func testVideoEmbedsALocalFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hs-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("example.mp4")
        let bytes = Data([0x00, 0x00, 0x00, 0x18])
        try bytes.write(to: file)
        let html = try DisplayLayout.render(
            json: #"{"title":"Example","modules":[{"type":"video","src":"example.mp4"}]}"#,
            baseDirectory: directory.path
        )
        XCTAssertTrue(html.contains("src=\"data:video/mp4;base64,\(bytes.base64EncodedString())\""))
        XCTAssertTrue(html.contains(" autoplay"))
    }

    func testVideoRejectsEmptySource() {
        assertRefusal(#"{"title":"Example","modules":[{"type":"video","src":""}]}"#)
        assertRefusal(#"{"title":"Example","modules":[{"type":"video","src":"  "}]}"#)
        assertRefusal(#"{"title":"Example","modules":[{"type":"video"}]}"#)
        assertRefusal(#"{"title":"Example","modules":[{"type":"video","src":"https://example.com/example.mp4","fit":""}]}"#)
        XCTAssertThrowsError(try DisplayPage(title: "Example", blocks: [.video(src: " ")])) { error in
            XCTAssertEqual((error as? HomeSignalError)?.exitCode, 1)
        }
    }

    func testDocsShowMediaShapes() throws {
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let agents = try String(contentsOfFile: "AGENTS.md", encoding: .utf8)
        let shapes = [
            #"{ "type": "html", "html": "<p>Example notice</p>" }"#,
            #"{ "type": "image", "src": "https://example.com/example.png", "fit": "contain", "caption": "Example" }"#,
            #"{ "type": "video", "src": "https://example.com/example.mp4", "fit": "cover", "autoplay": true, "muted": true, "loop": true }"#,
        ]
        for shape in shapes {
            XCTAssertTrue(readme.contains(shape), shape)
            XCTAssertTrue(agents.contains(shape), shape)
        }
    }
}

private func renderModule(_ module: String) throws -> String {
    try DisplayLayout.render(json: #"{"title":"Example","modules":[\#(module)]}"#)
}

private func moduleCount(_ html: String) -> Int {
    html.components(separatedBy: "class=\"block\" data-module=").count - 1
}

private func assertRefusal(_ json: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try DisplayLayout.render(json: json), json, file: file, line: line) { error in
        let signal = error as? HomeSignalError
        XCTAssertEqual(signal?.exitCode, 1, file: file, line: line)
        XCTAssertTrue(signal?.message.contains("Refusing to replace the screen.") == true, file: file, line: line)
    }
}
