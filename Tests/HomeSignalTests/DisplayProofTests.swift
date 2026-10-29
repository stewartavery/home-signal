import XCTest
@testable import HomeSignalCLI
@testable import HomeSignalCore

final class DisplayProofTests: XCTestCase {
    func testProofPixelsMatchTheScaleAt1080() {
        XCTAssertEqual(DisplayProof.stageWidth, 1920)
        XCTAssertEqual(DisplayProof.stageHeight, 1080)
        XCTAssertEqual(DisplayProof.pixels(vh: "0.8vh"), "8.64px")
        XCTAssertEqual(DisplayProof.pixels(vh: "1.6vh"), "17.28px")
        XCTAssertEqual(DisplayProof.pixels(vh: "2.4vh"), "25.92px")
        XCTAssertEqual(DisplayProof.pixels(vh: "3.6vh"), "38.88px")
        XCTAssertEqual(DisplayProof.pixels(vh: "4vh"), "43.2px")
        XCTAssertEqual(DisplayProof.pixels(vh: "5.4vh"), "58.32px")
        XCTAssertEqual(DisplayProof.pixels(vh: "6vh"), "64.8px")
        XCTAssertEqual(DisplayProof.pixels(vh: "8vh"), "86.4px")
        XCTAssertEqual(DisplayProof.pixels(vh: "12vh"), "129.6px")
        XCTAssertEqual(DisplayProof.pixels(vh: DisplaySpaceToken.l.value), "43.2px")
        XCTAssertEqual(DisplayProof.pixels(vh: DisplaySpaceToken.xl.value), "64.8px")
        XCTAssertEqual(DisplayProof.pixels(vh: DisplayTypeToken.xxl.value), "129.6px")
    }

    func testProofUsesBundledFontsAndAFixedStage() throws {
        let proof = try DisplayProof.render(json: DisplayLayout.reminderSpec)
        XCTAssertTrue(proof.contains("data-hs-proof=\"1\""))
        XCTAssertTrue(proof.contains("data-hs-ready"))
        XCTAssertTrue(proof.contains("1920px"))
        XCTAssertTrue(proof.contains("1080px"))
        XCTAssertTrue(proof.contains("animation:none"))
        XCTAssertTrue(proof.contains("transition:none"))
        XCTAssertTrue(proof.contains("caret-color:transparent"))
        XCTAssertTrue(proof.contains("font-display:block"))
        XCTAssertTrue(proof.contains("data:font/woff2;base64,"))
        XCTAssertTrue(proof.contains("format(\"woff2\")"))
        XCTAssertTrue(proof.contains("--space-l:43.2px"))
        XCTAssertTrue(proof.contains("--space-xl:64.8px"))
        XCTAssertTrue(proof.contains("\"HS Sans\""))
        XCTAssertFalse(proof.contains("data-hs-ready=\"1\""))
        for banned in ["system-ui", "-apple-system", "Helvetica", "Georgia", "Palatino", "ui-sans-serif", "ui-serif"] {
            XCTAssertFalse(proof.contains(banned), banned)
        }
        let production = try DisplayLayout.render(json: DisplayLayout.reminderSpec)
        XCTAssertFalse(production.contains("data-hs-proof"))
        XCTAssertFalse(production.contains("woff2"))
        XCTAssertFalse(production.contains("data-hs-ready"))
        XCTAssertNotEqual(ContentHash.sha256(proof), ContentHash.sha256(production))
        let again = try DisplayProof.render(json: DisplayLayout.reminderSpec)
        XCTAssertEqual(proof, again)
    }

    func testSerifThemeUsesTheSerifFace() throws {
        let html = try DisplayProof.render(json: DisplayLayout.scheduleSpec)
        XCTAssertTrue(html.contains("data-theme=\"moonlit-autumn\""))
        XCTAssertTrue(html.contains("--font:\"HS Serif\""))
        XCTAssertFalse(html.contains("--font:\"HS Sans\""))
        XCTAssertEqual(DisplayProof.fontFamily(for: DisplayThemes.neutral.fontFamily), "\"HS Sans\"")
        XCTAssertEqual(DisplayProof.fontFamily(for: DisplayThemes.moonlitAutumn.fontFamily), "\"HS Serif\"")
    }

    func testProofDoesNotInventPageContent() throws {
        let html = try DisplayProof.render(json: #"{"title":"Other","modules":[{"type":"message","text":"Other placeholder"}]}"#)
        XCTAssertTrue(html.contains("Other placeholder"))
        XCTAssertFalse(html.contains("Example reminder"))
        let destination = temporaryDirectory()
        XCTAssertThrowsError(try DisplayProof.exportSpec(json: "   ", name: "empty-page", theme: nil, outline: false, to: destination)) { error in
            let signal = error as? HomeSignalError
            XCTAssertEqual(signal?.exitCode, 1)
            XCTAssertTrue(signal?.message.contains("Refusing to replace the screen.") == true)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertThrowsError(try DisplayProof.exportSpec(json: "{}", name: "invalid-page", theme: nil, outline: false, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("invalid-page.html").path))
    }

    func testOutlineIsOptIn() throws {
        let plain = try DisplayProof.render(json: DisplayLayout.reminderSpec, outline: false)
        let outlined = try DisplayProof.render(json: DisplayLayout.reminderSpec, outline: true)
        XCTAssertFalse(plain.contains("outline:1px"))
        XCTAssertTrue(outlined.contains("outline:1px solid var(--accent)"))
        XCTAssertNotEqual(plain, outlined)
    }

    func testCatalogMatchesCommittedFixtures() throws {
        let repo = URL(fileURLWithPath: "Fixtures/DisplayProof", isDirectory: true)
        let catalog = try String(contentsOf: repo.appendingPathComponent("catalog.json"), encoding: .utf8)
        XCTAssertTrue(catalog.contains("message-default"))
        XCTAssertTrue(catalog.contains("grid-outline"))
        let message = try String(contentsOf: repo.appendingPathComponent("specs/message.json"), encoding: .utf8)
        let schedule = try String(contentsOf: repo.appendingPathComponent("specs/schedule.json"), encoding: .utf8)
        XCTAssertEqual(try canonicalJSON(message), try canonicalJSON(DisplayLayout.reminderSpec))
        XCTAssertEqual(try canonicalJSON(schedule), try canonicalJSON(DisplayLayout.scheduleSpec))

        let exported = try exportCopy(of: repo)
        let manifest = try decodeManifest(repo.appendingPathComponent(DisplayProof.manifestFile))
        XCTAssertEqual(manifest.algorithm, "sha256")
        XCTAssertEqual(manifest.stage, DisplayProofStage(width: 1920, height: 1080))
        XCTAssertEqual(manifest, exported)
        XCTAssertGreaterThanOrEqual(manifest.fixtures.count, 8)
        XCTAssertLessThanOrEqual(manifest.fixtures.count, 12)
        let themes = Set(manifest.fixtures.map(\.theme))
        XCTAssertTrue(themes.contains("default"))
        XCTAssertTrue(themes.contains("moonlit-autumn"))
        XCTAssertTrue(manifest.fixtures.contains { $0.outline })
        XCTAssertTrue(manifest.fixtures.contains { $0.overflow })
        XCTAssertTrue(manifest.fixtures.contains { $0.modules == 1 })
        XCTAssertTrue(manifest.fixtures.contains { $0.modules == 4 })
        var names = Set<String>()
        for fixture in manifest.fixtures {
            XCTAssertTrue(names.insert(fixture.name).inserted)
            let repoHTML = try Data(contentsOf: repo.appendingPathComponent(fixture.file))
            let text = String(decoding: repoHTML, as: UTF8.self)
            XCTAssertEqual(ContentHash.sha256(text), fixture.contentHash)
            XCTAssertTrue(text.contains("data-hs-proof=\"1\""))
            XCTAssertFalse(text.contains("system-ui"))
            if fixture.outline {
                XCTAssertTrue(text.contains("outline:1px"))
            } else {
                XCTAssertFalse(text.contains("outline:1px"))
            }
        }
    }

    func testProofExportDoesNotCallTheAgent() async throws {
        let destination = temporaryDirectory()
        try copyCatalog(to: destination)
        let client = ProofRejectingAgent()
        let sink = CollectingSink()
        let code = await CLI.run(
            ["--json", "display", "proof", "export", "--out", destination.path],
            hooks: CLIHooks(client: client, config: nil, sink: sink)
        )
        XCTAssertEqual(code, 0, sink.stdout() + sink.stderr())
        XCTAssertFalse(client.called)
        XCTAssertTrue(sink.stdout().contains("\"command\" : \"display.proof.export\""))
        XCTAssertTrue(sink.stdout().contains("message-default"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("message-default.html").path))

        let emptySink = CollectingSink()
        let empty = await CLI.run(
            ["--json", "display", "proof", "export", "--out", destination.path, "--spec", "  ", "--name", "blank"],
            hooks: CLIHooks(client: client, config: nil, sink: emptySink)
        )
        XCTAssertEqual(empty, 1)
        XCTAssertFalse(client.called)
        XCTAssertTrue(emptySink.stdout().contains("Refusing to replace the screen."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("blank.html").path))
    }

    func testRecordInstructionsStayOnTheContainer() throws {
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let agents = try String(contentsOfFile: "AGENTS.md", encoding: .utf8)
        let script = try String(contentsOfFile: "scripts/display-proof.sh", encoding: .utf8)
        let workflow = try String(contentsOfFile: ".github/workflows/display-proof.yml", encoding: .utf8)
        let config = try String(contentsOfFile: "VisualProof/playwright.config.ts", encoding: .utf8)
        let image = try String(contentsOfFile: "VisualProof/playwright-image.txt", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(image.hasPrefix("mcr.microsoft.com/playwright@sha256:"))
        XCTAssertGreaterThan(image.split(separator: ":").last?.count ?? 0, 60)
        for text in [readme, agents, script, workflow] {
            XCTAssertTrue(text.contains("playwright-image.txt"))
        }
        for text in [readme, agents, script] {
            XCTAssertTrue(text.contains("--update-snapshots=changed"))
        }
        XCTAssertTrue(workflow.contains("npx playwright test"))
        XCTAssertFalse(workflow.contains("--update-snapshots"))
        XCTAssertTrue(readme.contains("HS_MAC_PROOF"))
        XCTAssertTrue(agents.contains("HS_MAC_PROOF"))
        XCTAssertTrue(readme.contains("screenshots/darwin"))
        XCTAssertTrue(agents.contains("screenshots/darwin"))
        XCTAssertTrue(config.contains("HS_PROOF_CONTAINER"))
        XCTAssertTrue(config.contains("{platform}"))
        XCTAssertTrue(config.contains("deviceScaleFactor: 1"))
        XCTAssertTrue(config.contains("scale: 'css'"))
        XCTAssertTrue(config.contains("1920"))
        XCTAssertTrue(config.contains("1080"))
        XCTAssertFalse(config.contains("screenshots/darwin"))
    }

    private func exportCopy(of repo: URL) throws -> DisplayProofManifest {
        let destination = temporaryDirectory()
        try copyCatalog(from: repo, to: destination)
        return try DisplayProof.exportCatalog(in: destination)
    }

    private func copyCatalog(to destination: URL) throws {
        try copyCatalog(from: URL(fileURLWithPath: "Fixtures/DisplayProof", isDirectory: true), to: destination)
    }

    private func copyCatalog(from repo: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repo.appendingPathComponent("catalog.json"),
            to: destination.appendingPathComponent("catalog.json")
        )
        try FileManager.default.copyItem(
            at: repo.appendingPathComponent("specs"),
            to: destination.appendingPathComponent("specs")
        )
    }

    private func decodeManifest(_ url: URL) throws -> DisplayProofManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DisplayProofManifest.self, from: data)
    }

    private func canonicalJSON(_ text: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hs-proof-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class ProofRejectingAgent: AgentSending, @unchecked Sendable {
    var called = false

    func send(_ request: IPCRequest) async throws -> IPCResponse {
        called = true
        _ = request
        throw HomeSignalError.backend("agent should not be called")
    }
}
