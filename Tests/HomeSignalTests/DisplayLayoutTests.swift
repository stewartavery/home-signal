import XCTest
@testable import HomeSignalCLI
@testable import HomeSignalCore
@testable import HomeSignalDisplay
@testable import HomeSignalCapture
@testable import HomeSignalInput
@testable import HomeSignalKit
@testable import HomeSignalLights
@testable import HomeSignalMirroring

final class DisplayLayoutTests: XCTestCase {
    func testTypeAndSpaceTokens() {
        XCTAssertEqual(DisplayTypeToken.allCases.map(\.value), ["1.6vh", "2.4vh", "3.6vh", "5.4vh", "8vh", "12vh"])
        XCTAssertEqual(DisplayTypeToken.allCases.map(\.cssName), ["--type-xs", "--type-s", "--type-m", "--type-l", "--type-xl", "--type-xxl"])
        let typeSteps = [1.6, 2.4, 3.6, 5.4]
        for index in 1..<typeSteps.count {
            XCTAssertEqual(typeSteps[index] / typeSteps[index - 1], 1.5, accuracy: 0.0001)
        }
        XCTAssertEqual(12.0 / 8.0, 1.5, accuracy: 0.0001)
        XCTAssertEqual(DisplaySpaceToken.allCases.map(\.value), ["0.8vh", "1.6vh", "2.4vh", "4vh", "6vh"])
        XCTAssertEqual(DisplaySpaceToken.allCases.map(\.cssName), ["--space-xs", "--space-s", "--space-m", "--space-l", "--space-xl"])
        XCTAssertEqual(DisplayTokens.gap, .l)
        XCTAssertEqual(DisplayTokens.pageMargin, .xl)
        let css = DisplayTokens.rootCSS()
        for token in DisplayTypeToken.allCases {
            XCTAssertTrue(css.contains("\(token.cssName):\(token.value)"))
        }
        for token in DisplaySpaceToken.allCases {
            XCTAssertTrue(css.contains("\(token.cssName):\(token.value)"))
        }
    }

    func testCanvasUsesTheScaleAndFillsWithFlex() throws {
        let html = try DisplayLayout.render(json: DisplayLayout.reminderSpec)
        XCTAssertTrue(html.contains("aspect-ratio:16/9"))
        XCTAssertTrue(html.contains("padding:var(--space-xl)"))
        XCTAssertTrue(html.contains("display:grid"))
        XCTAssertTrue(html.contains("grid-auto-rows:minmax(0,1fr)"))
        XCTAssertTrue(html.contains("gap:var(--space-l)"))
        XCTAssertTrue(html.contains("flex:1"))
        XCTAssertTrue(html.contains(DisplayTokens.rootCSS()))
        XCTAssertTrue(html.contains("\"xs\",\"s\",\"m\",\"l\",\"xl\",\"xxl\""))
        XCTAssertEqual(moduleCount(html), 1)
        XCTAssertTrue(html.contains("data-module=\"message\""))
        XCTAssertTrue(html.contains("data-fit=\"xxl\""))
        XCTAssertEqual(DisplayTitle.parse(html), "Reminder")
    }

    func testThemesSwapWithoutChangingStructure() throws {
        let neutral = try DisplayLayout.render(json: DisplayLayout.scheduleSpec, theme: "default")
        let moonlit = try DisplayLayout.render(json: DisplayLayout.scheduleSpec)
        XCTAssertEqual(moduleBody(neutral), moduleBody(moonlit))
        XCTAssertTrue(neutral.contains("data-theme=\"default\""))
        XCTAssertTrue(neutral.contains(DisplayThemes.neutral.background))
        XCTAssertTrue(neutral.contains(DisplayThemes.neutral.fontFamily))
        XCTAssertFalse(neutral.contains(DisplayThemes.moonlitAutumn.accent))
        XCTAssertTrue(moonlit.contains("data-theme=\"moonlit-autumn\""))
        XCTAssertTrue(moonlit.contains(DisplayThemes.moonlitAutumn.accent))
        XCTAssertTrue(moonlit.contains(DisplayThemes.moonlitAutumn.fontFamily))
        XCTAssertFalse(moonlit.contains(DisplayThemes.neutral.background))
        XCTAssertEqual(DisplayTitle.parse(moonlit), "Example day")
    }

    func testOmittedThemeUsesDefault() throws {
        let html = try renderModule(#"{"type":"message","text":"Example reminder"}"#)
        XCTAssertTrue(html.contains("data-theme=\"default\""))
    }

    func testThemeOverrideReplacesTheSpecTheme() throws {
        let html = try DisplayLayout.render(json: DisplayLayout.reminderSpec, theme: "moonlit-autumn")
        XCTAssertTrue(html.contains("data-theme=\"moonlit-autumn\""))
        XCTAssertTrue(html.contains(DisplayThemes.moonlitAutumn.canvas))
    }

    func testRendersHeader() throws {
        let html = try renderModule(#"{"type":"header","title":"Fish & Chips <lunch>","subtitle":"Placeholder","size":"l"}"#)
        XCTAssertTrue(html.contains("data-module=\"header\""))
        XCTAssertTrue(html.contains("<h1>Fish &amp; Chips &lt;lunch&gt;</h1>"))
        XCTAssertTrue(html.contains("Placeholder"))
        XCTAssertTrue(html.contains("data-fit=\"l\""))
        XCTAssertFalse(html.contains("<lunch>"))
    }

    func testRendersMessage() throws {
        let html = try renderModule(#"{"type":"message","text":"Example reminder"}"#)
        XCTAssertTrue(html.contains("data-module=\"message\""))
        XCTAssertTrue(html.contains("<p>Example reminder</p>"))
        XCTAssertTrue(html.contains("data-fit=\"xxl\""))
        XCTAssertFalse(html.contains("class=\"message\""))
    }

    func testRendersColumns() throws {
        let html = try renderModule(
            #"{"type":"columns","columns":[{"title":"Morning","items":[{"leading":"09:00","text":"A & B"}]},{"title":"Afternoon","items":["Example item"]}]}"#
        )
        XCTAssertTrue(html.contains("data-module=\"columns\""))
        XCTAssertTrue(html.contains("class=\"cols\""))
        XCTAssertEqual(html.components(separatedBy: "class=\"col\"").count - 1, 2)
        XCTAssertTrue(html.contains("Morning"))
        XCTAssertTrue(html.contains("Afternoon"))
        XCTAssertTrue(html.contains("09:00"))
        XCTAssertTrue(html.contains("A &amp; B"))
        XCTAssertTrue(html.contains("Example item"))
        XCTAssertTrue(html.contains("data-fit=\"s\""))
        XCTAssertFalse(html.contains("A & B"))
    }

    func testRendersList() throws {
        let html = try renderModule(
            #"{"type":"list","title":"Later","size":"s","items":[{"leading":"18:00","text":"Example item"}]}"#
        )
        XCTAssertTrue(html.contains("data-module=\"list\""))
        XCTAssertTrue(html.contains("Later"))
        XCTAssertTrue(html.contains("18:00"))
        XCTAssertTrue(html.contains("Example item"))
        XCTAssertTrue(html.contains("data-fit=\"s\""))
        XCTAssertTrue(html.contains("class=\"rows\""))
    }

    func testRendersSummary() throws {
        let html = try renderModule(
            #"{"type":"summary","label":"Next","value":"Example item","detail":"09:00"}"#
        )
        XCTAssertTrue(html.contains("data-module=\"summary\""))
        XCTAssertTrue(html.contains("Next"))
        XCTAssertTrue(html.contains("Example item"))
        XCTAssertTrue(html.contains("09:00"))
        XCTAssertTrue(html.contains("data-fit=\"xl\""))
    }

    func testRendersAlert() throws {
        let html = try renderModule(
            #"{"type":"alert","level":"critical","title":"Notice","text":"Example notice"}"#
        )
        XCTAssertTrue(html.contains("data-module=\"alert\""))
        XCTAssertTrue(html.contains("data-level=\"critical\""))
        XCTAssertTrue(html.contains("role=\"alert\""))
        XCTAssertTrue(html.contains("Notice"))
        XCTAssertTrue(html.contains("Example notice"))
        XCTAssertTrue(html.contains("data-fit=\"l\""))
        XCTAssertTrue(html.contains("var(--alert-foreground)"))
    }

    func testScheduleSpecRendersEverySection() throws {
        let html = try DisplayLayout.render(json: DisplayLayout.scheduleSpec)
        XCTAssertTrue(html.contains("data-module=\"header\""))
        XCTAssertTrue(html.contains("data-module=\"columns\""))
        XCTAssertTrue(html.contains("data-module=\"summary\""))
        XCTAssertTrue(html.contains("Morning"))
        XCTAssertTrue(html.contains("Afternoon"))
        XCTAssertTrue(html.contains("Example meeting"))
        XCTAssertEqual(moduleCount(html), 3)
        let again = try DisplayLayout.render(json: DisplayLayout.scheduleSpec)
        XCTAssertEqual(html, again)
    }

    func testAddingAModuleKeepsTheCanvasRules() throws {
        let one = try DisplayLayout.render(json: DisplayLayout.reminderSpec)
        let json = """
        {"title":"Example day","modules":[{"type":"message","text":"Example reminder"},{"type":"alert","text":"Example notice"}]}
        """
        let two = try DisplayLayout.render(json: json)
        XCTAssertEqual(moduleCount(one), 1)
        XCTAssertEqual(moduleCount(two), 2)
        XCTAssertTrue(two.contains("flex:1"))
        XCTAssertTrue(two.contains("gap:var(--space-l)"))
        XCTAssertTrue(two.contains("Example notice"))
    }

    func testSpecRejectsEmptyAndInvalidInput() {
        let samples = [
            "",
            "   ",
            "{",
            "null",
            "[]",
            "{}",
            #"{"title":"Example","modules":[]}"#,
            #"{"title":"   ","modules":[{"type":"message","text":"Example"}]}"#,
            #"{"title":"Example\nday","modules":[{"type":"message","text":"Example"}]}"#,
            #"{"title":"Example","theme":"","modules":[{"type":"message","text":"Example"}]}"#,
            #"{"title":"Example","theme":"nope","modules":[{"type":"message","text":"Example"}]}"#,
            #"{"title":"Example","modules":[{"type":"widget","text":"Example"}]}"#,
            #"{"title":"Example","modules":[{"text":"Example"}]}"#,
            #"{"title":"Example","modules":[{"type":"message","text":"   "}]}"#,
            #"{"title":"Example","modules":[{"type":"message","text":"Example","size":"huge"}]}"#,
            #"{"title":"Example","modules":[{"type":"message","text":"Example","size":""}]}"#,
            #"{"title":"Example","modules":[{"type":"header"}]}"#,
            #"{"title":"Example","modules":[{"type":"header","title":"  "}]}"#,
            #"{"title":"Example","modules":[{"type":"columns","columns":[]}]}"#,
            #"{"title":"Example","modules":[{"type":"columns","columns":[{"title":"Morning","items":[]}]}]}"#,
            #"{"title":"Example","modules":[{"type":"columns","columns":[{"items":[{"text":"  "}]}]}]}"#,
            #"{"title":"Example","modules":[{"type":"list","items":[]}]}"#,
            #"{"title":"Example","modules":[{"type":"list","items":[{"leading":"09:00"}]}]}"#,
            #"{"title":"Example","modules":[{"type":"summary","label":"Next"}]}"#,
            #"{"title":"Example","modules":[{"type":"summary","label":" ","value":"Example"}]}"#,
            #"{"title":"Example","modules":[{"type":"alert","text":""}]}"#,
            #"{"title":"Example","modules":[{"type":"alert","text":"Example","level":"panic"}]}"#,
            #"{"title":"Example","modules":[{"type":"alert","text":"Example","level":""}]}"#,
        ]
        for sample in samples {
            XCTAssertThrowsError(try DisplayLayout.render(json: sample), sample) { error in
                let signal = error as? HomeSignalError
                XCTAssertEqual(signal?.exitCode, 1, sample)
                XCTAssertEqual(signal?.code, "usage", sample)
                XCTAssertTrue(signal?.message.contains("Refusing to replace the screen.") == true, sample)
            }
        }
        XCTAssertThrowsError(try DisplayLayout.render(json: DisplayLayout.reminderSpec, theme: " ")) { error in
            let signal = error as? HomeSignalError
            XCTAssertEqual(signal?.exitCode, 1)
            XCTAssertTrue(signal?.message.contains("Refusing to replace the screen.") == true)
        }
    }

    func testSwiftPageRejectsBlankModules() {
        XCTAssertThrowsError(try DisplayPage(title: "Example", blocks: [.message(text: "  ")])) { error in
            XCTAssertEqual((error as? HomeSignalError)?.exitCode, 1)
        }
        XCTAssertThrowsError(try DisplayPage(title: " ", blocks: [.message(text: "Example")]))
        XCTAssertThrowsError(try DisplayPage(title: "Example", blocks: []))
    }

    func testLayoutKindRejectsEmptyHTML() {
        let document = DisplayDocument(
            kind: DisplayKind.layout,
            html: " \n",
            background: "#000000",
            foreground: "#ffffff",
            accent: "#99ccff",
            messageSize: "10vw",
            titleSize: "6vw",
            rowSize: "3.2vw"
        )
        XCTAssertThrowsError(try DisplayRendering.prepare(document)) { error in
            let signal = error as? HomeSignalError
            XCTAssertEqual(signal?.exitCode, 1)
            XCTAssertTrue(signal?.message.contains("Refusing to replace the screen.") == true)
        }
    }

    func testLayoutShowVerifiesReadbackAndEmptyDoesNotReplace() async throws {
        let display = SimulatedDisplay()
        let runtime = makeLayoutRuntime(display: display)
        let custom = "<html><head><title>Custom</title></head><body><p>Custom page</p></body></html>"
        let shown = try await showLayout(runtime, kind: DisplayKind.html, html: custom)
        XCTAssertEqual(shown.title, "Custom")
        XCTAssertTrue(shown.verified)
        let kept = await display.presentedHTML()
        XCTAssertEqual(kept, custom)

        let rendered = try DisplayLayout.render(json: DisplayLayout.reminderSpec)
        do {
            _ = try await showLayout(runtime, kind: DisplayKind.layout, html: "  ")
            XCTFail("empty layout should fail")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.exitCode, 1)
        }
        let afterEmpty = await display.presentedHTML()
        XCTAssertEqual(afterEmpty, custom)

        let layout = try await showLayout(runtime, kind: DisplayKind.layout, html: rendered)
        XCTAssertTrue(layout.verified)
        XCTAssertEqual(layout.title, "Reminder")
        XCTAssertEqual(layout.kind, DisplayKind.layout)
        XCTAssertEqual(layout.contentHash, ContentHash.sha256(rendered))
        let afterLayout = await display.presentedHTML()
        XCTAssertEqual(afterLayout, rendered)

        let response = await runtime.handle(
            IPCRequest(
                method: IPCMethod.displayShow,
                params: try layoutParams(html: try DisplayLayout.render(json: DisplayLayout.scheduleSpec)).jsonValue(),
                dryRun: true
            )
        )
        XCTAssertTrue(response.ok)
        let afterDryRun = await display.presentedHTML()
        XCTAssertEqual(afterDryRun, rendered)
    }

    func testCLIRejectsEmptyLayoutWithoutCallingAgent() async {
        let client = LayoutRejectingAgent()
        let sink = CollectingSink()
        let empty = await CLI.run(
            ["display", "layout", "--spec", "   "],
            hooks: CLIHooks(client: client, config: .standard, sink: sink)
        )
        XCTAssertEqual(empty, 1)
        XCTAssertFalse(client.called)
        XCTAssertTrue(sink.stderr().contains("Refusing"))

        let invalid = await CLI.run(
            ["--json", "display", "layout", "--spec", "{}"],
            hooks: CLIHooks(client: client, config: .standard, sink: CollectingSink())
        )
        XCTAssertEqual(invalid, 1)
        XCTAssertFalse(client.called)

        let missing = await CLI.run(
            ["display", "layout"],
            hooks: CLIHooks(client: client, config: .standard, sink: CollectingSink())
        )
        XCTAssertEqual(missing, 1)
        XCTAssertFalse(client.called)

        let both = await CLI.run(
            ["display", "layout", "--file", "spec.json", "--spec", "{}"],
            hooks: CLIHooks(client: client, config: .standard, sink: CollectingSink())
        )
        XCTAssertEqual(both, 1)
        XCTAssertFalse(client.called)
    }

    func testCLILayoutRoundTripVerifiesTheScreen() async throws {
        let rendered = try DisplayLayout.render(json: DisplayLayout.reminderSpec)
        let path = "/tmp/hs-layout-\(UUID().uuidString).json"
        try Data(DisplayLayout.reminderSpec.utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let display = SimulatedDisplay()
        let runtime = makeLayoutRuntime(display: display)
        let stop = StopFlag()
        let socket = "/tmp/hs-\(UUID().uuidString).sock"
        let server = Task { try await AgentServer.serve(runtime: runtime, stop: stop, path: socket) }
        defer { stop.stop() }
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: socket) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let sink = CollectingSink()
        let code = await CLI.run(
            ["--json", "display", "layout", "--theme", "moonlit-autumn", "--file", path],
            hooks: CLIHooks(client: SocketAgentClient(socketPath: socket, timeoutSeconds: 10), config: .standard, sink: sink)
        )
        let themed = try DisplayLayout.render(json: DisplayLayout.reminderSpec, theme: "moonlit-autumn")
        XCTAssertEqual(code, 0, sink.stdout() + sink.stderr())
        XCTAssertTrue(sink.stdout().contains(ContentHash.sha256(themed)))
        XCTAssertTrue(sink.stdout().contains("\"verified\" : true"))
        XCTAssertTrue(sink.stdout().contains("Reminder"))
        XCTAssertTrue(sink.stdout().contains("\"kind\" : \"layout\""))
        XCTAssertTrue(sink.stdout().contains("data-theme=\\\"moonlit-autumn\\\""))
        let shown = await display.presentedHTML()
        XCTAssertEqual(shown, themed)
        XCTAssertNotEqual(shown, rendered)
        stop.stop()
        _ = try await server.value
    }

    func testDocsDescribeTokensAndExamples() throws {
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let agents = try String(contentsOfFile: "AGENTS.md", encoding: .utf8)
        for token in DisplayTypeToken.allCases {
            XCTAssertTrue(readme.contains(token.value), token.rawValue)
            XCTAssertTrue(agents.contains(token.value), token.rawValue)
            XCTAssertTrue(readme.contains(token.cssName), token.cssName)
        }
        for token in DisplaySpaceToken.allCases {
            XCTAssertTrue(readme.contains(token.value), token.rawValue)
            XCTAssertTrue(agents.contains(token.value), token.rawValue)
        }
        XCTAssertTrue(readme.contains(DisplayLayout.reminderSpec))
        XCTAssertTrue(readme.contains(DisplayLayout.scheduleSpec))
        XCTAssertTrue(agents.contains(DisplayLayout.reminderSpec))
        XCTAssertTrue(agents.contains(DisplayLayout.scheduleSpec))
        XCTAssertTrue(agents.contains("display layout"))
        XCTAssertTrue(agents.contains("Example reminder"))
        XCTAssertTrue(agents.contains("moonlit-autumn"))
        XCTAssertTrue(readme.contains("flex: 1"))
        XCTAssertTrue(agents.contains("flex: 1"))
    }
}

private func renderModule(_ module: String) throws -> String {
    try DisplayLayout.render(json: #"{"title":"Example","modules":[\#(module)]}"#)
}

private func moduleCount(_ html: String) -> Int {
    html.components(separatedBy: "class=\"block\" data-module=").count - 1
}

private func moduleBody(_ html: String) -> String {
    guard let start = html.range(of: "<div class=\"page\">"), let end = html.range(of: "</div></div><script>") else {
        return html
    }
    return String(html[start.lowerBound..<end.lowerBound])
}

private func makeLayoutRuntime(display: any DisplayChannel) -> AgentRuntime {
    let config = HomeSignalConfig.standard
    return AgentRuntime(
        config: config,
        lights: SimulatedLightBackend(config: config.simulated),
        display: display,
        mirror: SimulatedMirror(),
        input: SimulatedPointer(),
        capture: SimulatedCapture(),
        sleeper: ImmediateSleeper()
    )
}

private func layoutParams(html: String) -> DisplayShowParams {
    let config = HomeSignalConfig.standard
    let document = DisplayDocument(
        kind: DisplayKind.layout,
        html: html,
        background: config.display.background,
        foreground: config.display.foreground,
        accent: config.display.accent,
        messageSize: config.display.messageSize,
        titleSize: config.display.titleSize,
        rowSize: config.display.rowSize
    )
    return DisplayShowParams(document: document, present: true)
}

private func showLayout(_ runtime: AgentRuntime, kind: String, html: String) async throws -> DisplayShowResult {
    let config = HomeSignalConfig.standard
    let params = DisplayShowParams(
        document: DisplayDocument(
            kind: kind,
            html: html,
            background: config.display.background,
            foreground: config.display.foreground,
            accent: config.display.accent,
            messageSize: config.display.messageSize,
            titleSize: config.display.titleSize,
            rowSize: config.display.rowSize
        ),
        present: true
    )
    let response = await runtime.handle(
        IPCRequest(method: IPCMethod.displayShow, params: try params.jsonValue())
    )
    if let error = response.error, !response.ok {
        throw error.error
    }
    guard let result = response.result else {
        throw HomeSignalError.backend("empty display response")
    }
    return try result.decode(DisplayShowResult.self)
}

private final class LayoutRejectingAgent: AgentSending, @unchecked Sendable {
    var called = false

    func send(_ request: IPCRequest) async throws -> IPCResponse {
        called = true
        _ = request
        throw HomeSignalError.backend("agent should not be called")
    }
}
