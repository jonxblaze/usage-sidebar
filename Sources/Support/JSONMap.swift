import Foundation

/// Loose JSON walker that accepts camelCase and snake_case without inventing values.
struct JSONMap {
    let object: [String: Any]

    init?(_ any: Any?) {
        if let dict = any as? [String: Any] {
            object = dict
        } else {
            return nil
        }
    }

    static func parse(_ data: Data) -> JSONMap? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return JSONMap(obj)
    }

    func map(_ keys: String...) -> JSONMap? {
        JSONMap(any(keys))
    }

    func array(_ keys: String...) -> [Any]? {
        any(keys) as? [Any]
    }

    func string(_ keys: String...) -> String? {
        let value = any(keys)
        if let s = value as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return nil
    }

    func bool(_ keys: String...) -> Bool? {
        let value = any(keys)
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    func double(_ keys: String...) -> Double? {
        Self.number(any(keys))
    }

    func any(_ keys: [String]) -> Any? {
        for key in keys {
            if let v = object[key], !(v is NSNull) { return v }
        }
        let lowered = Set(keys.map { $0.lowercased().replacingOccurrences(of: "_", with: "") })
        for (k, v) in object {
            let compact = k.lowercased().replacingOccurrences(of: "_", with: "")
            if lowered.contains(compact), !(v is NSNull) { return v }
        }
        return nil
    }

    func any(_ keys: String...) -> Any? { any(keys) }

    static func number(_ value: Any?) -> Double? {
        if value is NSNull { return nil }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}

enum TokenScan {
    /// Pull a Google OAuth access token out of JSON, base64, or protobuf-ish bytes.
    /// Never logs the token.
    static func googleAccessToken(in data: Data, depth: Int = 0) -> String? {
        if depth > 4 { return nil }
        if let text = String(data: data, encoding: .utf8) {
            if let json = try? JSONSerialization.jsonObject(with: text.data(using: .utf8) ?? data),
               let found = googleAccessToken(inJSON: json) {
                return found
            }
            if let found = firstMatch(in: text, prefix: "ya29.") { return found }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeBase64(trimmed), let decoded = Data(base64Encoded: trimmed) {
                return googleAccessToken(in: decoded, depth: depth + 1)
            }
        }
        if let found = firstASCII(in: data, prefix: "ya29.") { return found }
        if let decoded = Data(base64Encoded: data) {
            return googleAccessToken(in: decoded, depth: depth + 1)
        }
        return nil
    }

    static func googleAccessToken(inJSON json: Any) -> String? {
        if let s = json as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("ya29.") { return t }
            return nil
        }
        if let dict = json as? [String: Any] {
            for key in ["access_token", "accessToken"] {
                if let s = dict[key] as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.count > 20 { return t }
                }
            }
            if let nested = dict["token"] {
                if let found = googleAccessToken(inJSON: nested) { return found }
            }
            for value in dict.values {
                if let found = googleAccessToken(inJSON: value) { return found }
            }
        }
        if let arr = json as? [Any] {
            for value in arr {
                if let found = googleAccessToken(inJSON: value) { return found }
            }
        }
        return nil
    }

    private static func firstMatch(in text: String, prefix: String) -> String? {
        guard let range = text.range(of: prefix) else { return nil }
        let rest = text[range.lowerBound...]
        let token = rest.prefix(while: { ch in
            ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "." || ch == "~"
        })
        return token.count > prefix.count + 8 ? String(token) : nil
    }

    private static func firstASCII(in data: Data, prefix: String) -> String? {
        guard let needle = prefix.data(using: .utf8) else { return nil }
        guard let found = data.range(of: needle) else { return nil }
        var end = found.lowerBound
        let bytes = data
        while end < bytes.count {
            let b = bytes[end]
            let ok = (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
                || b == 45 || b == 95 || b == 46 || b == 126
            if !ok { break }
            end += 1
        }
        let slice = bytes.subdata(in: found.lowerBound..<end)
        guard let s = String(data: slice, encoding: .utf8), s.count > prefix.count + 8 else { return nil }
        return s
    }

    private static func looksLikeBase64(_ s: String) -> Bool {
        guard s.count >= 32, s.count % 4 == 0 else { return false }
        return s.unicodeScalars.allSatisfy { ch in
            CharacterSet.alphanumerics.contains(ch) || ch == "+" || ch == "/" || ch == "="
        }
    }
}
