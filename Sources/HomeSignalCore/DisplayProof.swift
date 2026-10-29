import Foundation

public struct DisplayProofStage: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct DisplayProofFixture: Codable, Equatable, Sendable {
    public var name: String
    public var file: String
    public var title: String
    public var theme: String
    public var modules: Int
    public var outline: Bool
    public var overflow: Bool
    public var contentHash: String

    public init(
        name: String,
        file: String,
        title: String,
        theme: String,
        modules: Int,
        outline: Bool,
        overflow: Bool,
        contentHash: String
    ) {
        self.name = name
        self.file = file
        self.title = title
        self.theme = theme
        self.modules = modules
        self.outline = outline
        self.overflow = overflow
        self.contentHash = contentHash
    }
}

public struct DisplayProofManifest: Codable, Equatable, Sendable {
    public var algorithm: String
    public var stage: DisplayProofStage
    public var fixtures: [DisplayProofFixture]

    public init(algorithm: String, stage: DisplayProofStage, fixtures: [DisplayProofFixture]) {
        self.algorithm = algorithm
        self.stage = stage
        self.fixtures = fixtures
    }
}

public enum DisplayProof {
    public static let stageWidth = 1920
    public static let stageHeight = 1080
    public static let catalogFile = "catalog.json"
    public static let manifestFile = "manifest.json"

    public static func render(json: String, theme themeOverride: String? = nil, outline: Bool = false) throws -> String {
        let page = try DisplayLayout.page(json: json, theme: themeOverride)
        let theme = try DisplayThemes.named(page.themeID)
        var proofTheme = theme
        proofTheme.fontFamily = fontFamily(for: theme.fontFamily)
        return try DisplayLayout.render(page: page, theme: proofTheme, proofCSS: try proofCSS(outline: outline))
    }

    public static func exportCatalog(in directory: URL) throws -> DisplayProofManifest {
        let catalogURL = directory.appendingPathComponent(catalogFile)
        guard FileManager.default.fileExists(atPath: catalogURL.path) else {
            throw HomeSignalError.usage("display proof export needs \(catalogFile) in --out, or pass --file or --spec with --name.")
        }
        let catalog = try decodeCatalog(at: catalogURL)
        guard !catalog.fixtures.isEmpty else {
            throw HomeSignalError.displayRefusal("Proof catalog needs at least one fixture.")
        }
        var seen = Set<String>()
        let rendered: [(DisplayProofFixture, String)] = try catalog.fixtures.map { item in
            let name = try fixtureName(item.name)
            guard seen.insert(name).inserted else {
                throw HomeSignalError.usage("Proof catalog repeats fixture \"\(name)\".")
            }
            let specURL = try specURL(item.spec, in: directory)
            let json = try readUTF8(specURL, empty: "Proof spec is empty.")
            let html = try render(json: json, theme: item.theme, outline: item.outline ?? false)
            let page = try DisplayLayout.page(json: json, theme: item.theme)
            let fixture = DisplayProofFixture(
                name: name,
                file: "\(name).html",
                title: page.title,
                theme: page.themeID,
                modules: page.blocks.count,
                outline: item.outline ?? false,
                overflow: item.overflow ?? false,
                contentHash: ContentHash.sha256(html)
            )
            return (fixture, html)
        }
        return try write(rendered, to: directory, replaceHTML: true)
    }

    public static func exportSpec(
        json: String,
        name: String,
        theme: String?,
        outline: Bool,
        to directory: URL
    ) throws -> DisplayProofManifest {
        let fixtureName = try fixtureName(name)
        let html = try render(json: json, theme: theme, outline: outline)
        let page = try DisplayLayout.page(json: json, theme: theme)
        let fixture = DisplayProofFixture(
            name: fixtureName,
            file: "\(fixtureName).html",
            title: page.title,
            theme: page.themeID,
            modules: page.blocks.count,
            outline: outline,
            overflow: false,
            contentHash: ContentHash.sha256(html)
        )
        return try write([(fixture, html)], to: directory, replaceHTML: false)
    }

    static func fontFamily(for stack: String) -> String {
        let lower = stack.lowercased()
        let serif = lower.contains("serif") && !lower.contains("sans-serif") && !lower.contains("sans serif")
        return serif ? "\"HS Serif\"" : "\"HS Sans\""
    }

    static func pixels(vh text: String) -> String {
        guard text.hasSuffix("vh") else { return text }
        let number = text.dropLast(2)
        let tenths: Int
        if let dot = number.firstIndex(of: ".") {
            let whole = Int(number[..<dot]) ?? 0
            let frac = number[number.index(after: dot)...]
            guard frac.count == 1, let digit = Int(frac) else { return text }
            tenths = whole * 10 + digit
        } else {
            guard let whole = Int(number) else { return text }
            tenths = whole * 10
        }
        let numerator = stageHeight * tenths
        let whole = numerator / 1000
        var frac = numerator % 1000
        if frac == 0 { return "\(whole)px" }
        var digits = ""
        var scale = 100
        while frac > 0 {
            digits.append(Character(UnicodeScalar(48 + frac / scale)!))
            frac = frac % scale
            scale /= 10
            if scale == 0 { break }
        }
        return "\(whole).\(digits)px"
    }

    private static func proofCSS(outline: Bool) throws -> String {
        let tokens = (DisplayTypeToken.allCases.map { "\($0.cssName):\(pixels(vh: $0.value))" }
            + DisplaySpaceToken.allCases.map { "\($0.cssName):\(pixels(vh: $0.value))" })
            .joined(separator: ";")
        let outlineRule = outline
            ? "html[data-hs-proof] .block{outline:1px solid var(--accent);outline-offset:-1px}"
            : ""
        return """
        \(try fontCSS())
        html[data-hs-proof]{\(tokens)}
        html[data-hs-proof],html[data-hs-proof] body{width:\(stageWidth)px;height:\(stageHeight)px;overflow:hidden}
        html[data-hs-proof] .stage{width:\(stageWidth)px;height:\(stageHeight)px;min-width:\(stageWidth)px;min-height:\(stageHeight)px;max-width:\(stageWidth)px;max-height:\(stageHeight)px;flex:none;aspect-ratio:auto;overflow:hidden}
        html[data-hs-proof],html[data-hs-proof] *{animation:none !important;transition:none !important;caret-color:transparent}
        \(outlineRule)
        """
    }

    private static func fontCSS() throws -> String {
        let faces: [(String, Int, String)] = [
            ("HS Sans", 500, "hs-sans-500"),
            ("HS Sans", 600, "hs-sans-600"),
            ("HS Serif", 500, "hs-serif-500"),
            ("HS Serif", 600, "hs-serif-600"),
        ]
        return try faces.map { family, weight, resource in
            let uri = try fontDataURI(resource)
            return "@font-face{font-family:\"\(family)\";font-style:normal;font-weight:\(weight);font-display:block;src:url(\"\(uri)\") format(\"woff2\")}"
        }.joined(separator: "\n")
    }

    private static func fontDataURI(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "woff2", subdirectory: "ProofFonts")
            ?? Bundle.module.url(forResource: name, withExtension: "woff2")
        guard let url else {
            throw HomeSignalError.backend("Missing proof font \(name).woff2.")
        }
        let data = try Data(contentsOf: url)
        guard data.starts(with: [0x77, 0x4f, 0x46, 0x32]) else {
            throw HomeSignalError.backend("Proof font \(name).woff2 is not a WOFF2 file.")
        }
        return "data:font/woff2;base64,\(data.base64EncodedString())"
    }

    private static func write(
        _ rendered: [(DisplayProofFixture, String)],
        to directory: URL,
        replaceHTML: Bool
    ) throws -> DisplayProofManifest {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keep = Set(rendered.map { $0.0.file })
        if replaceHTML {
            let existing = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for url in existing where url.pathExtension == "html" && !keep.contains(url.lastPathComponent) {
                try FileManager.default.removeItem(at: url)
            }
        }
        let root = Self.directoryPath(directory)
        for (fixture, html) in rendered {
            let url = directory.appendingPathComponent(fixture.file)
            guard Self.directoryPath(url.deletingLastPathComponent()) == root else {
                throw HomeSignalError.usage("Proof fixture path is invalid.")
            }
            try Data(html.utf8).write(to: url)
            let written = try String(contentsOf: url, encoding: .utf8)
            guard ContentHash.sha256(written) == fixture.contentHash else {
                throw HomeSignalError.backend("Proof fixture \(fixture.name) changed while it was written.")
            }
        }
        let manifest = DisplayProofManifest(
            algorithm: "sha256",
            stage: DisplayProofStage(width: stageWidth, height: stageHeight),
            fixtures: rendered.map(\.0)
        )
        let data = try JSONEncoder.pretty.encode(manifest)
        var text = String(decoding: data, as: UTF8.self)
        if !text.hasSuffix("\n") { text += "\n" }
        try Data(text.utf8).write(to: directory.appendingPathComponent(manifestFile))
        return manifest
    }

    private static func decodeCatalog(at url: URL) throws -> DisplayProofCatalog {
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(DisplayProofCatalog.self, from: data)
        } catch {
            throw HomeSignalError.usage("Proof catalog is invalid.")
        }
    }

    private static func specURL(_ relative: String, in directory: URL) throws -> URL {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains(".."), !relative.contains("\\") else {
            throw HomeSignalError.usage("Proof catalog spec path is invalid.")
        }
        let url = directory.appendingPathComponent(relative).standardizedFileURL
        let root = directory.standardizedFileURL.path
        guard url.path == root || url.path.hasPrefix(root + "/") else {
            throw HomeSignalError.usage("Proof catalog spec path is invalid.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw HomeSignalError.displayRefusal("Proof spec was not found.")
        }
        return url
    }

    private static func readUTF8(_ url: URL, empty: String) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw HomeSignalError.displayRefusal("Proof spec must be UTF-8.")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HomeSignalError.displayRefusal(empty)
        }
        return text
    }

    private static func directoryPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private static func fixtureName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let ok = !name.isEmpty
            && name.count <= 80
            && name.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !name.hasPrefix("-")
            && !name.hasSuffix("-")
            && !name.contains("--")
        guard ok else {
            throw HomeSignalError.usage("Proof fixture name must be lowercase words separated by single hyphens.")
        }
        return name
    }
}

private struct DisplayProofCatalog: Decodable {
    var fixtures: [DisplayProofCatalogItem]
}

private struct DisplayProofCatalogItem: Decodable {
    var name: String
    var spec: String
    var theme: String?
    var outline: Bool?
    var overflow: Bool?
}
