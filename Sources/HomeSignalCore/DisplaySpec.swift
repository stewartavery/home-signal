import Foundation

public enum DisplayModuleKind: String, CaseIterable, Sendable {
    case header
    case message
    case columns
    case list
    case summary
    case alert
}

public enum DisplayAlertLevel: String, CaseIterable, Sendable {
    case info
    case warning
    case critical
}

public struct DisplayRow: Sendable, Equatable {
    public var leading: String?
    public var text: String

    public init(leading: String? = nil, text: String) {
        self.leading = leading
        self.text = text
    }
}

public struct DisplayColumn: Sendable, Equatable {
    public var title: String?
    public var items: [DisplayRow]

    public init(title: String? = nil, items: [DisplayRow]) {
        self.title = title
        self.items = items
    }
}

public enum DisplayBlock: Sendable, Equatable {
    case header(title: String, subtitle: String? = nil, size: DisplayTypeToken = .xl)
    case message(text: String, size: DisplayTypeToken = .xxl)
    case columns(columns: [DisplayColumn], size: DisplayTypeToken = .s)
    case list(title: String? = nil, items: [DisplayRow], size: DisplayTypeToken = .m)
    case summary(label: String, value: String, detail: String? = nil, size: DisplayTypeToken = .xl)
    case alert(title: String? = nil, text: String, level: DisplayAlertLevel = .info, size: DisplayTypeToken = .l)

    func validated() throws -> DisplayBlock {
        switch self {
        case .header(let title, let subtitle, let size):
            let trimmed = try required(title, "A header module needs a title.")
            return .header(title: trimmed, subtitle: optional(subtitle), size: size)
        case .message(let text, let size):
            return .message(text: try required(text, "A message module needs text."), size: size)
        case .columns(let columns, let size):
            guard !columns.isEmpty else {
                throw HomeSignalError.displayRefusal("A columns module needs at least one column.")
            }
            let ready = try columns.map { column -> DisplayColumn in
                guard !column.items.isEmpty else {
                    throw HomeSignalError.displayRefusal("A column needs at least one item.")
                }
                let items = try column.items.map { try $0.validated() }
                return DisplayColumn(title: optional(column.title), items: items)
            }
            return .columns(columns: ready, size: size)
        case .list(let title, let items, let size):
            guard !items.isEmpty else {
                throw HomeSignalError.displayRefusal("A list module needs at least one item.")
            }
            return .list(title: optional(title), items: try items.map { try $0.validated() }, size: size)
        case .summary(let label, let value, let detail, let size):
            return .summary(
                label: try required(label, "A summary module needs a label and a value."),
                value: try required(value, "A summary module needs a label and a value."),
                detail: optional(detail),
                size: size
            )
        case .alert(let title, let text, let level, let size):
            return .alert(title: optional(title), text: try required(text, "An alert module needs text."), level: level, size: size)
        }
    }
}

public struct DisplayPage: Sendable, Equatable {
    public let title: String
    public let themeID: String
    public let blocks: [DisplayBlock]

    public init(title: String, themeID: String = DisplayThemes.defaultID, blocks: [DisplayBlock]) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw HomeSignalError.displayRefusal("Layout spec needs a title.")
        }
        guard !trimmedTitle.contains(where: \.isNewline) else {
            throw HomeSignalError.displayRefusal("Layout title must be one line.")
        }
        guard !blocks.isEmpty else {
            throw HomeSignalError.displayRefusal("Layout spec needs at least one module.")
        }
        let theme = try DisplayThemes.named(themeID)
        self.title = trimmedTitle
        self.themeID = theme.id
        self.blocks = try blocks.map { try $0.validated() }
    }
}

extension DisplayRow {
    func validated() throws -> DisplayRow {
        let text = try required(text, "A list item needs text.")
        return DisplayRow(leading: optional(leading), text: text)
    }
}

func optional(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func required(_ value: String, _ message: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw HomeSignalError.displayRefusal(message) }
    return trimmed
}

struct LayoutSpecDTO: Decodable {
    var title: String?
    var theme: String?
    var modules: [LayoutModuleDTO]?
}

struct LayoutModuleDTO: Decodable {
    var type: String?
    var title: String?
    var subtitle: String?
    var text: String?
    var size: String?
    var label: String?
    var value: String?
    var detail: String?
    var level: String?
    var items: [LayoutItemDTO]?
    var columns: [LayoutColumnDTO]?
}

struct LayoutColumnDTO: Decodable {
    var title: String?
    var items: [LayoutItemDTO]?
}

struct LayoutItemDTO: Decodable {
    var leading: String?
    var text: String?

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        switch value {
        case .string(let text):
            self.text = text
            self.leading = nil
        case .object(let fields):
            leading = Self.string(fields["leading"])
            text = Self.string(fields["text"])
            if fields["text"] != nil && text == nil {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "item text must be a string"))
            }
            if fields["leading"] != nil && leading == nil {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "item leading must be a string"))
            }
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "item must be a string or an object"))
        }
    }

    private static func string(_ value: JSONValue?) -> String? {
        if case .string(let text) = value { return text }
        return nil
    }
}

enum LayoutModuleParser {
    static func block(_ dto: LayoutModuleDTO, index: Int) throws -> DisplayBlock {
        let kindName = dto.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard let kind = DisplayModuleKind(rawValue: kindName) else {
            if kindName.isEmpty {
                throw HomeSignalError.displayRefusal("Module \(index) needs a type.")
            }
            throw HomeSignalError.displayRefusal("Module \(index) has an unknown type \"\(kindName)\".")
        }
        let size = try parseSize(dto.size, index: index, kind: kindName)
        switch kind {
        case .header:
            let title = try field(dto.title, index: index, kind: kindName, name: "title")
            return .header(title: title, subtitle: optional(dto.subtitle), size: size ?? .xl)
        case .message:
            let text = try field(dto.text, index: index, kind: kindName, name: "text")
            return .message(text: text, size: size ?? .xxl)
        case .columns:
            guard let columns = dto.columns, !columns.isEmpty else {
                throw HomeSignalError.displayRefusal("Module \(index) (columns) needs at least one column.")
            }
            let ready = try columns.enumerated().map { offset, column in
                let items = try rows(column.items, index: index, kind: "columns column \(offset + 1)")
                return DisplayColumn(title: optional(column.title), items: items)
            }
            return .columns(columns: ready, size: size ?? .s)
        case .list:
            let items = try rows(dto.items, index: index, kind: kindName)
            return .list(title: optional(dto.title), items: items, size: size ?? .m)
        case .summary:
            let label = try field(dto.label, index: index, kind: kindName, name: "label")
            let value = try field(dto.value, index: index, kind: kindName, name: "value")
            return .summary(label: label, value: value, detail: optional(dto.detail), size: size ?? .xl)
        case .alert:
            let text = try field(dto.text, index: index, kind: kindName, name: "text")
            let level = try parseLevel(dto.level, index: index)
            return .alert(title: optional(dto.title), text: text, level: level, size: size ?? .l)
        }
    }

    private static func rows(_ items: [LayoutItemDTO]?, index: Int, kind: String) throws -> [DisplayRow] {
        guard let items, !items.isEmpty else {
            throw HomeSignalError.displayRefusal("Module \(index) (\(kind)) needs at least one item.")
        }
        return try items.enumerated().map { offset, item in
            let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                throw HomeSignalError.displayRefusal("Module \(index) (\(kind)) item \(offset + 1) needs text.")
            }
            return DisplayRow(leading: optional(item.leading), text: text)
        }
    }

    private static func field(_ value: String?, index: Int, kind: String, name: String) throws -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw HomeSignalError.displayRefusal("Module \(index) (\(kind)) needs \(name).")
        }
        return trimmed
    }

    private static func parseSize(_ raw: String?, index: Int, kind: String) throws -> DisplayTypeToken? {
        guard let raw else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else {
            throw HomeSignalError.displayRefusal("Module \(index) (\(kind)) has an empty size.")
        }
        guard let token = DisplayTypeToken(rawValue: name) else {
            throw HomeSignalError.displayRefusal("Module \(index) (\(kind)) has an unknown size \"\(name)\".")
        }
        return token
    }

    private static func parseLevel(_ raw: String?, index: Int) throws -> DisplayAlertLevel {
        guard let raw else { return .info }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else {
            throw HomeSignalError.displayRefusal("Module \(index) (alert) has an empty level.")
        }
        guard let level = DisplayAlertLevel(rawValue: name) else {
            throw HomeSignalError.displayRefusal("Module \(index) (alert) has an unknown level \"\(name)\".")
        }
        return level
    }
}
