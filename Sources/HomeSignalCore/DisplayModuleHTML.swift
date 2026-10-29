import Foundation

enum DisplayModuleHTML {
    static func render(_ block: DisplayBlock) -> String {
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
        }
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
