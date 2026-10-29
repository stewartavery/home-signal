import Foundation

enum DisplayModuleHTML {
    static func render(_ block: DisplayBlock, baseDirectory: String?) throws -> String {
        switch block {
        case .header(let title, let subtitle, let size):
            var inner = "<h1>\(escape(title))</h1>"
            if let subtitle {
                inner += "<p class=\"kicker\">\(escape(subtitle))</p>"
            }
            return section("header", fluid(size, inner))
        case .message(let text, let size):
            return section("message", fluid(size, "<p>\(escape(text))</p>"))
        case .columns(let columns, let size):
            let cells = columns.map { column in
                var body = ""
                if let title = column.title {
                    body += "<h2 class=\"col-title\">\(escape(title))</h2>"
                }
                body += rows(column.items, size: size)
                return "<div class=\"col\">\(body)</div>"
            }.joined()
            return section("columns", "<div class=\"cols\">\(cells)</div>")
        case .list(let title, let items, let size):
            let heading = title.map { "<h2 class=\"heading\">\(escape($0))</h2>" } ?? ""
            return section("list", heading + rows(items, size: size))
        case .summary(let label, let value, let detail, let size):
            var inner = "<p class=\"kicker\">\(escape(label))</p><p class=\"value\">\(escape(value))</p>"
            if let detail {
                inner += "<p class=\"kicker\">\(escape(detail))</p>"
            }
            return section("summary", fluid(size, inner))
        case .alert(let title, let text, let level, let size):
            var inner = ""
            if let title {
                inner += "<p class=\"kicker\">\(escape(title))</p>"
            }
            inner += "<p>\(escape(text))</p>"
            return section("alert", fluid(size, inner), level: level)
        case .html(let html):
            return section("html", "<iframe class=\"embed\" srcdoc=\"\(escape(html))\"></iframe>")
        case .image(let src, let fit, let caption):
            let resolved = try DisplayMediaSource.resolve(src, kind: .image, baseDirectory: baseDirectory)
            return section("image", mediaTag("img", src: resolved, fit: fit, caption: caption))
        case .video(let src, let fit, let caption, let autoplay, let muted, let loop):
            let resolved = try DisplayMediaSource.resolve(src, kind: .video, baseDirectory: baseDirectory)
            return section("video", mediaTag("video", src: resolved, fit: fit, caption: caption, autoplay: autoplay, muted: muted, loop: loop))
        }
    }

    private static func mediaTag(
        _ tag: String,
        src: String,
        fit: DisplayMediaFit,
        caption: String?,
        autoplay: Bool = false,
        muted: Bool = false,
        loop: Bool = false
    ) -> String {
        var attributes = [
            "class=\"media\"",
            "data-fit=\"\(fit.rawValue)\"",
            "src=\"\(escape(src))\"",
        ]
        if tag == "img" {
            attributes.append("alt=\"\(escape(caption ?? ""))\"")
        } else {
            attributes.append("playsinline")
            if autoplay { attributes.append("autoplay") }
            if muted { attributes.append("muted") }
            if loop { attributes.append("loop") }
        }
        let void = tag == "img" ? ">" : "></\(tag)>"
        let captionHTML = caption.map { "<p class=\"caption\">\(escape($0))</p>" } ?? ""
        return "<div class=\"media-slot\"><\(tag) \(attributes.joined(separator: " "))\(void)</div>\(captionHTML)"
    }

    private static func section(_ kind: String, _ body: String, level: DisplayAlertLevel? = nil) -> String {
        let tag = kind == "header" ? "header" : "section"
        let levelAttr = level.map { " data-level=\"\($0.rawValue)\"" } ?? ""
        let role = kind == "alert" ? " role=\"alert\"" : ""
        return "<\(tag) class=\"block\" data-module=\"\(kind)\"\(levelAttr)\(role)>\(body)</\(tag)>"
    }

    private static func fluid(_ size: DisplayTypeToken, _ body: String) -> String {
        "<div class=\"fit grow\" data-fit=\"\(size.rawValue)\" style=\"--fit-max:var(\(size.cssName))\"><div class=\"inner center\">\(body)</div></div>"
    }

    private static func rows(_ items: [DisplayRow], size: DisplayTypeToken) -> String {
        let lines = items.map { item in
            let lead = item.leading.map { "<span class=\"leading\">\(escape($0))</span>" } ?? ""
            return "<li class=\"row\"><div class=\"inner start\">\(lead)<span class=\"text\">\(escape(item.text))</span></div></li>"
        }.joined()
        return "<ul class=\"rows\" data-fit=\"\(size.rawValue)\" style=\"--fit-max:var(\(size.cssName))\">\(lines)</ul>"
    }

    private static func escape(_ text: String) -> String {
        DisplayRendering.escape(text)
    }
}
