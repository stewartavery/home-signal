import Foundation

public enum DisplayTypeToken: String, CaseIterable, Sendable {
    case xs
    case s
    case m
    case l
    case xl
    case xxl

    public var cssName: String { "--type-\(rawValue)" }

    public var value: String {
        switch self {
        case .xs: "1.6vh"
        case .s: "2.4vh"
        case .m: "3.6vh"
        case .l: "5.4vh"
        case .xl: "8vh"
        case .xxl: "12vh"
        }
    }
}

public enum DisplaySpaceToken: String, CaseIterable, Sendable {
    case xs
    case s
    case m
    case l
    case xl

    public var cssName: String { "--space-\(rawValue)" }

    public var value: String {
        switch self {
        case .xs: "0.8vh"
        case .s: "1.6vh"
        case .m: "2.4vh"
        case .l: "4vh"
        case .xl: "6vh"
        }
    }
}

public enum DisplayTokens {
    public static let gap = DisplaySpaceToken.l
    public static let pageMargin = DisplaySpaceToken.xl

    public static func rootCSS() -> String {
        var rules: [String] = []
        rules.append(contentsOf: DisplayTypeToken.allCases.map { "\($0.cssName):\($0.value)" })
        rules.append(contentsOf: DisplaySpaceToken.allCases.map { "\($0.cssName):\($0.value)" })
        return ":root{\(rules.joined(separator: ";"))}"
    }
}
