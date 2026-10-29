public enum TOMLValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([TOMLValue])
    case table([String: TOMLValue])

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var int: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value) where value.rounded() == value: return Int(value)
        default: return nil
        }
    }

    public var double: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var array: [TOMLValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var table: [String: TOMLValue]? {
        if case .table(let value) = self { return value }
        return nil
    }
}

public struct TOMLParseError: Error, Equatable, CustomStringConvertible {
    public var line: Int
    public var message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }

    public var description: String {
        "TOML line \(line): \(message)"
    }
}

public struct TOMLParser {
    private let text: String
    private var index: String.Index
    private var line = 1

    public init(_ text: String) {
        self.text = text
        self.index = text.startIndex
    }

    public static func parse(_ text: String) throws -> [String: TOMLValue] {
        var parser = TOMLParser(text)
        return try parser.parseDocument()
    }

    private mutating func parseDocument() throws -> [String: TOMLValue] {
        var root: [String: TOMLValue] = [:]
        var context = Context.root
        while true {
            try skipTrivia()
            if done { break }
            if peek() == "[" {
                context = try parseHeader(into: &root)
                try finishLine()
            } else {
                let key = try parseKey()
                try skipSpaces()
                guard consume("=") else { throw error("expected = after key") }
                try skipSpaces()
                let value = try parseValue()
                try put(value, key: key, context: context, into: &root)
                try finishLine()
            }
        }
        return root
    }

    private struct Context {
        var path: [String]
        var arrayPath: [String]?
        static let root = Context(path: [], arrayPath: nil)
    }

    private var done: Bool { index == text.endIndex }

    private func peek() -> Character? {
        done ? nil : text[index]
    }

    private mutating func advance() {
        guard !done else { return }
        if text[index] == "\n" { line += 1 }
        index = text.index(after: index)
    }

    private mutating func consume(_ character: Character) -> Bool {
        guard peek() == character else { return false }
        advance()
        return true
    }

    private func error(_ message: String) -> TOMLParseError {
        TOMLParseError(line: line, message: message)
    }

    private mutating func skipTrivia() throws {
        while !done {
            if peek() == " " || peek() == "\t" || peek() == "\r" || peek() == "\n" {
                advance()
            } else if peek() == "#" {
                skipComment()
            } else {
                break
            }
        }
    }

    private mutating func skipSpaces() {
        while peek() == " " || peek() == "\t" { advance() }
    }

    private mutating func skipComment() {
        while !done && peek() != "\n" { advance() }
    }

    private mutating func finishLine() throws {
        skipSpaces()
        if peek() == "#" { skipComment() }
        if done { return }
        if peek() == "\r" { advance() }
        if peek() == "\n" {
            advance()
            return
        }
        throw error("unexpected \(String(peek() ?? "?")) after value")
    }

    private mutating func parseHeader(into root: inout [String: TOMLValue]) throws -> Context {
        advance()
        let array = consume("[")
        try skipSpaces()
        let path = try parseKey()
        try skipSpaces()
        guard consume("]") else { throw error("expected ]") }
        if array {
            guard consume("]") else { throw error("expected ]]") }
            try appendArrayTable(&root, path: path)
            return Context(path: [], arrayPath: path)
        }
        try ensureTable(&root, path: path)
        return Context(path: path, arrayPath: nil)
    }

    private mutating func parseKey() throws -> [String] {
        var parts: [String] = []
        while true {
            try skipSpaces()
            if peek() == "\"" || peek() == "'" {
                parts.append(try parseString())
            } else {
                let start = index
                while let character = peek(), character.isLetter || character.isNumber || character == "_" || character == "-" {
                    advance()
                }
                guard index != start else { throw error("expected key") }
                parts.append(String(text[start..<index]))
            }
            try skipSpaces()
            if consume(".") {
                continue
            }
            break
        }
        return parts
    }

    private mutating func parseValue() throws -> TOMLValue {
        if peek() == "\"" || peek() == "'" {
            return .string(try parseString())
        }
        if peek() == "[" {
            return .array(try parseArray())
        }
        if peek() == "{" {
            return .table(try parseInlineTable())
        }
        if looking(at: "true") {
            skipWord(4)
            return .bool(true)
        }
        if looking(at: "false") {
            skipWord(5)
            return .bool(false)
        }
        return try parseNumber()
    }

    private func looking(at word: String) -> Bool {
        text[index...].hasPrefix(word)
    }

    private mutating func skipWord(_ count: Int) {
        for _ in 0..<count { advance() }
    }

    private mutating func parseString() throws -> String {
        let quote = peek()
        guard quote == "\"" || quote == "'" else { throw error("expected string") }
        advance()
        var value = ""
        while !done && peek() != quote {
            if quote == "\"" && peek() == "\\" {
                advance()
                guard let escaped = peek() else { throw error("bad escape") }
                advance()
                switch escaped {
                case "n": value.append("\n")
                case "t": value.append("\t")
                case "r": value.append("\r")
                case "\\": value.append("\\")
                case "\"": value.append("\"")
                default: throw error("unsupported escape \\\(escaped)")
                }
            } else {
                value.append(peek()!)
                advance()
            }
        }
        guard consume(quote!) else { throw error("unterminated string") }
        return value
    }

    private mutating func parseArray() throws -> [TOMLValue] {
        guard consume("[") else { throw error("expected [") }
        var values: [TOMLValue] = []
        while true {
            try skipTrivia()
            if consume("]") { break }
            values.append(try parseValue())
            try skipTrivia()
            if consume(",") { continue }
            try skipTrivia()
            guard consume("]") else { throw error("expected ]") }
            break
        }
        return values
    }

    private mutating func parseInlineTable() throws -> [String: TOMLValue] {
        guard consume("{") else { throw error("expected {") }
        var table: [String: TOMLValue] = [:]
        while true {
            try skipTrivia()
            if consume("}") { break }
            let key = try parseKey()
            try skipSpaces()
            guard consume("=") else { throw error("expected = in inline table") }
            try skipSpaces()
            let value = try parseValue()
            try insert(&table, path: key, value: value)
            try skipTrivia()
            if consume(",") { continue }
            try skipTrivia()
            guard consume("}") else { throw error("expected }") }
            break
        }
        return table
    }

    private mutating func parseNumber() throws -> TOMLValue {
        let start = index
        if peek() == "-" { advance() }
        guard peek()?.isNumber == true else { throw error("expected value") }
        while peek()?.isNumber == true { advance() }
        var isDouble = false
        if peek() == "." {
            isDouble = true
            advance()
            guard peek()?.isNumber == true else { throw error("expected digits after decimal") }
            while peek()?.isNumber == true { advance() }
        }
        let token = String(text[start..<index])
        if isDouble {
            guard let value = Double(token) else { throw error("bad number \(token)") }
            return .double(value)
        }
        guard let value = Int(token) else { throw error("bad integer \(token)") }
        return .int(value)
    }

    private mutating func put(_ value: TOMLValue, key: [String], context: Context, into root: inout [String: TOMLValue]) throws {
        if let arrayPath = context.arrayPath {
            try mutateLastArrayTable(&root, path: arrayPath) { table in
                try insert(&table, path: key, value: value)
            }
        } else {
            try insert(&root, path: context.path + key, value: value)
        }
    }

    private func insert(_ table: inout [String: TOMLValue], path: [String], value: TOMLValue) throws {
        guard let head = path.first else { throw error("empty key") }
        if path.count == 1 {
            if table[head] != nil { throw error("duplicate key \(head)") }
            table[head] = value
            return
        }
        if table[head] == nil { table[head] = .table([:]) }
        guard case .table(var child) = table[head] else { throw error("\(head) is not a table") }
        try insert(&child, path: Array(path.dropFirst()), value: value)
        table[head] = .table(child)
    }

    private func ensureTable(_ table: inout [String: TOMLValue], path: [String]) throws {
        guard let head = path.first else { return }
        if table[head] == nil { table[head] = .table([:]) }
        guard case .table(var child) = table[head] else { throw error("\(head) is not a table") }
        if path.count > 1 {
            try ensureTable(&child, path: Array(path.dropFirst()))
            table[head] = .table(child)
        }
    }

    private func appendArrayTable(_ table: inout [String: TOMLValue], path: [String]) throws {
        guard let head = path.first else { throw error("empty array table") }
        if path.count == 1 {
            var elements = table[head]?.array ?? []
            if table[head] != nil && table[head]?.array == nil {
                throw error("\(head) is not an array of tables")
            }
            elements.append(.table([:]))
            table[head] = .array(elements)
            return
        }
        if table[head] == nil { table[head] = .table([:]) }
        guard case .table(var child) = table[head] else { throw error("\(head) is not a table") }
        try appendArrayTable(&child, path: Array(path.dropFirst()))
        table[head] = .table(child)
    }

    private func mutateLastArrayTable(
        _ table: inout [String: TOMLValue],
        path: [String],
        body: (inout [String: TOMLValue]) throws -> Void
    ) throws {
        guard let head = path.first else { return }
        if path.count == 1 {
            guard case .array(var elements) = table[head], !elements.isEmpty else {
                throw error("missing array table \(head)")
            }
            guard case .table(var last) = elements[elements.count - 1] else {
                throw error("array element is not a table")
            }
            try body(&last)
            elements[elements.count - 1] = .table(last)
            table[head] = .array(elements)
            return
        }
        guard case .table(var child) = table[head] else { throw error("\(head) is not a table") }
        try mutateLastArrayTable(&child, path: Array(path.dropFirst()), body: body)
        table[head] = .table(child)
    }
}
