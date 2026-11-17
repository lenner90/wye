import Foundation

/// Reads and edits one top-level key of a JSON object as raw bytes, leaving every
/// other byte of the document exactly as it was. Used for `~/.claude.json`, which
/// holds a lot of unrelated state that must not be reformatted or lose precision.
public enum TopLevelJSON {
    struct Member {
        let key: String
        let keyStart: Int
        let valueStart: Int
        let valueEnd: Int  // exclusive
    }

    struct Layout {
        let members: [Member]
        let closeBrace: Int
    }

    public static func value(forKey key: String, in data: Data) throws -> Data? {
        let bytes = [UInt8](data)
        guard let m = try scan(bytes).members.first(where: { $0.key == key }) else { return nil }
        return Data(bytes[m.valueStart..<m.valueEnd])
    }

    public static func setting(key: String, rawValue: Data, in data: Data) throws -> Data {
        guard (try? JSONSerialization.jsonObject(with: rawValue, options: .fragmentsAllowed)) != nil else {
            throw WyeError.malformedJSON
        }
        var bytes = [UInt8](data)
        let layout = try scan(bytes)
        if let m = layout.members.first(where: { $0.key == key }) {
            bytes.replaceSubrange(m.valueStart..<m.valueEnd, with: rawValue)
        } else {
            let keyData = try JSONSerialization.data(withJSONObject: key, options: .fragmentsAllowed)
            if let last = layout.members.last {
                let insert = Array(",\n  ".utf8) + Array(keyData) + Array(": ".utf8) + Array(rawValue)
                bytes.insert(contentsOf: insert, at: last.valueEnd)
            } else {
                bytes.insert(contentsOf: Array(keyData) + Array(": ".utf8) + Array(rawValue), at: layout.closeBrace)
            }
        }
        return try validated(bytes)
    }

    public static func removing(key: String, from data: Data) throws -> Data {
        var bytes = [UInt8](data)
        let members = try scan(bytes).members
        guard let index = members.firstIndex(where: { $0.key == key }) else { return data }
        let m = members[index]
        if index < members.count - 1 {
            bytes.removeSubrange(m.keyStart..<members[index + 1].keyStart)
        } else if index > 0 {
            bytes.removeSubrange(members[index - 1].valueEnd..<m.valueEnd)
        } else {
            bytes.removeSubrange(m.keyStart..<m.valueEnd)
        }
        return try validated(bytes)
    }

    private static func validated(_ bytes: [UInt8]) throws -> Data {
        let data = Data(bytes)
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw WyeError.malformedJSON
        }
        return data
    }

    static func scan(_ b: [UInt8]) throws -> Layout {
        let n = b.count
        var i = 0

        func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 }
        func skipSpace() { while i < n, isSpace(b[i]) { i += 1 } }

        func skipString() throws {
            i += 1
            while i < n {
                if b[i] == UInt8(ascii: "\\") { i += 2; continue }
                if b[i] == UInt8(ascii: "\"") { i += 1; return }
                i += 1
            }
            throw WyeError.malformedJSON
        }

        func skipValue() throws {
            guard i < n else { throw WyeError.malformedJSON }
            switch b[i] {
            case UInt8(ascii: "\""):
                try skipString()
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                var depth = 0
                while i < n {
                    let c = b[i]
                    if c == UInt8(ascii: "\"") { try skipString(); continue }
                    if c == UInt8(ascii: "{") || c == UInt8(ascii: "[") { depth += 1 }
                    if c == UInt8(ascii: "}") || c == UInt8(ascii: "]") {
                        depth -= 1
                        if depth == 0 { i += 1; return }
                    }
                    i += 1
                }
                throw WyeError.malformedJSON
            default:
                let start = i
                while i < n, !isSpace(b[i]), b[i] != UInt8(ascii: ","), b[i] != UInt8(ascii: "}") {
                    i += 1
                }
                if i == start { throw WyeError.malformedJSON }
            }
        }

        skipSpace()
        guard i < n, b[i] == UInt8(ascii: "{") else { throw WyeError.malformedJSON }
        i += 1
        var members: [Member] = []
        skipSpace()
        if i < n, b[i] == UInt8(ascii: "}") { return Layout(members: [], closeBrace: i) }

        while true {
            skipSpace()
            guard i < n, b[i] == UInt8(ascii: "\"") else { throw WyeError.malformedJSON }
            let keyStart = i
            try skipString()
            let decoded = try? JSONSerialization.jsonObject(
                with: Data(b[keyStart..<i]), options: .fragmentsAllowed)
            guard let key = decoded as? String else { throw WyeError.malformedJSON }
            skipSpace()
            guard i < n, b[i] == UInt8(ascii: ":") else { throw WyeError.malformedJSON }
            i += 1
            skipSpace()
            let valueStart = i
            try skipValue()
            members.append(Member(key: key, keyStart: keyStart, valueStart: valueStart, valueEnd: i))
            skipSpace()
            guard i < n else { throw WyeError.malformedJSON }
            if b[i] == UInt8(ascii: ",") { i += 1; continue }
            if b[i] == UInt8(ascii: "}") { return Layout(members: members, closeBrace: i) }
            throw WyeError.malformedJSON
        }
    }
}
