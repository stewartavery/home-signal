import Foundation

public enum DisplayMediaFit: String, CaseIterable, Sendable {
    case contain
    case cover
}

enum DisplayMediaSource {
    enum Kind {
        case image
        case video
    }

    static func resolve(_ src: String, kind: Kind, baseDirectory: String?) throws -> String {
        let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HomeSignalError.displayRefusal("A media module needs a src.")
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("data:") {
            return trimmed
        }
        let path = try filePath(trimmed, baseDirectory: baseDirectory)
        return try embed(path, kind: kind)
    }

    private static func filePath(_ src: String, baseDirectory: String?) throws -> String {
        if src.lowercased().hasPrefix("file:") {
            guard let url = URL(string: src), url.isFileURL, !url.path.isEmpty else {
                throw HomeSignalError.displayRefusal("Layout media file was not found.")
            }
            return url.path
        }
        let expanded = HomeSignalPaths.expand(src)
        if expanded.hasPrefix("/") {
            return expanded
        }
        let base = baseDirectory ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: base).appendingPathComponent(expanded).path
    }

    private static func embed(_ path: String, kind: Kind) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            throw HomeSignalError.displayRefusal("Layout media file was not found: \(path).")
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw HomeSignalError.displayRefusal("Layout media file could not be read: \(path).")
        }
        guard !data.isEmpty else {
            throw HomeSignalError.displayRefusal("Layout media file is empty: \(path).")
        }
        guard let mime = mimeType(path, kind: kind) else {
            throw HomeSignalError.displayRefusal("Layout media file type is not supported: \(path).")
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private static func mimeType(_ path: String, kind: Kind) -> String? {
        switch (kind, URL(fileURLWithPath: path).pathExtension.lowercased()) {
        case (.image, "png"):
            "image/png"
        case (.image, "jpg"), (.image, "jpeg"):
            "image/jpeg"
        case (.image, "gif"):
            "image/gif"
        case (.image, "webp"):
            "image/webp"
        case (.image, "svg"):
            "image/svg+xml"
        case (.image, "bmp"):
            "image/bmp"
        case (.image, "avif"):
            "image/avif"
        case (.video, "mp4"), (.video, "m4v"):
            "video/mp4"
        case (.video, "webm"):
            "video/webm"
        case (.video, "ogv"), (.video, "ogg"):
            "video/ogg"
        case (.video, "mov"):
            "video/quicktime"
        default:
            nil
        }
    }
}
