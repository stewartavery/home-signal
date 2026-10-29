import Foundation

public enum ContentHash {
    public static func sha256(_ text: String) -> String {
        SHA256.hex(Array(text.utf8))
    }
}

public enum DisplayTitle {
    public static func parse(_ html: String) -> String? {
        guard let open = html.range(of: "<title>", options: [.caseInsensitive]) else { return nil }
        guard let close = html.range(of: "</title>", options: [.caseInsensitive], range: open.upperBound..<html.endIndex) else { return nil }
        let raw = html[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = decode(String(raw))
        return decoded.isEmpty ? nil : decoded
    }

    private static func decode(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

public enum DisplayRendering {
    public struct Prepared: Sendable, Equatable {
        public var html: String
        public var readback: DisplayReadback
    }

    public static func prepare(_ document: DisplayDocument) throws -> Prepared {
        let html = try markup(for: document)
        let title = DisplayTitle.parse(html)
        return Prepared(
            html: html,
            readback: DisplayReadback(contentHash: ContentHash.sha256(html), title: title, kind: document.kind)
        )
    }

    public static func markup(for document: DisplayDocument) throws -> String {
        switch document.kind {
        case DisplayKind.message:
            let text = document.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                throw HomeSignalError.usage("display message needs the text to show. Refusing to replace the screen.")
            }
            return renderGenerated(document)
        case DisplayKind.schedule:
            let title = document.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else {
                throw HomeSignalError.usage("display schedule needs a title. Refusing to replace the screen.")
            }
            guard !document.rows.isEmpty else {
                throw HomeSignalError.usage("display schedule needs at least one row. Refusing to replace the screen.")
            }
            return renderGenerated(document)
        case DisplayKind.html:
            guard let html = document.html, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HomeSignalError.usage("display html needs a file or an HTML string. Refusing to replace custom content.")
            }
            return html
        case DisplayKind.clear:
            return renderGenerated(document)
        default:
            throw HomeSignalError.usage("Unknown display kind \(document.kind).")
        }
    }

    public static func renderGenerated(_ document: DisplayDocument) -> String {
        let trimmedTitle = document.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = document.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageTitle = ((trimmedTitle?.isEmpty == false) ? trimmedTitle : nil)
            ?? ((trimmedMessage?.isEmpty == false) ? trimmedMessage : nil)
            ?? ""
        let body: String
        switch document.kind {
        case DisplayKind.message:
            let heading = document.title.map { "<h1>\(escape($0))</h1>" } ?? ""
            body = "<body class=\"message\">\(heading)<p>\(escape(document.message ?? ""))</p></body>"
        case DisplayKind.schedule:
            let rows = document.rows.map { row in
                "<tr><td class=\"time\">\(escape(row.time))</td><td>\(escape(row.label))</td></tr>"
            }.joined()
            body = "<body class=\"schedule\"><h1>\(escape(document.title ?? ""))</h1><table>\(rows)</table></body>"
        default:
            body = "<body></body>"
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>\(escape(pageTitle))</title><style>
        html,body{margin:0;height:100%;background:\(document.background);color:\(document.foreground)}
        body{display:flex;flex-direction:column;align-items:center;justify-content:center;box-sizing:border-box;padding:4vw;text-align:center;font:16px -apple-system,Helvetica,sans-serif}
        body.message{font-weight:700;font-size:\(document.messageSize)}
        h1{font-size:\(document.titleSize);margin:0 0 3vh;font-weight:700}
        table{font-size:\(document.rowSize);border-collapse:collapse}
        td{padding:1vh 2vw}
        td.time{color:\(document.accent);text-align:right;white-space:nowrap}
        </style></head>\(body)</html>
        """
    }

    public static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum SHA256 {
    static func hex(_ message: [UInt8]) -> String {
        digest(message).map { String(format: "%02x", $0) }.joined()
    }

    static func digest(_ message: [UInt8]) -> [UInt8] {
        var hash: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        var bytes = message
        let bitLength = UInt64(message.count) &* 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }
        for offset in stride(from: 0, to: bytes.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let start = offset + index * 4
                words[index] = UInt32(bytes[start]) << 24
                    | UInt32(bytes[start + 1]) << 16
                    | UInt32(bytes[start + 2]) << 8
                    | UInt32(bytes[start + 3])
            }
            for index in 16..<64 {
                let s0 = rotate(words[index - 15], 7) ^ rotate(words[index - 15], 18) ^ (words[index - 15] >> 3)
                let s1 = rotate(words[index - 2], 17) ^ rotate(words[index - 2], 19) ^ (words[index - 2] >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }
            var a = hash[0], b = hash[1], c = hash[2], d = hash[3]
            var e = hash[4], f = hash[5], g = hash[6], h = hash[7]
            for index in 0..<64 {
                let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
                let choose = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ choose &+ k[index] &+ words[index]
                let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ majority
                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }
            hash[0] = hash[0] &+ a
            hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c
            hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e
            hash[5] = hash[5] &+ f
            hash[6] = hash[6] &+ g
            hash[7] = hash[7] &+ h
        }
        return hash.flatMap { word in
            [
                UInt8((word >> 24) & 0xff),
                UInt8((word >> 16) & 0xff),
                UInt8((word >> 8) & 0xff),
                UInt8(word & 0xff),
            ]
        }
    }

    private static func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]
}
