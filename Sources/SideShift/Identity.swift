import CryptoKit
import Foundation

/// Hashes identity the way the SideShift link page and the server expect: SHA-256 in lower-case hex.
enum IdentityHasher {
    /// The trimmed, lower-cased email; nil when it does not look like an email.
    static func email(_ raw: String) -> String? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else { return nil }
        return sha256(normalized)
    }

    /// The phone's digits with country code and no leading zeros or +; nil when too short to be a phone number.
    static func phone(_ raw: String) -> String? {
        var digits = raw.filter(\.isNumber)
        while digits.hasPrefix("0") { digits.removeFirst() }
        guard (7...15).contains(digits.count) else { return nil }
        return sha256(digits)
    }

    /// The Instagram username, lower-cased, without @ or a profile URL around it; nil when it cannot be a username.
    static func instagram(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = name.range(of: "instagram.com/") { name = String(name[range.upperBound...]) }
        name = name.split(separator: "/").first.map(String.init) ?? ""
        name = name.split(separator: "?").first.map(String.init) ?? ""
        while name.hasPrefix("@") { name.removeFirst() }
        guard name.range(of: #"^[a-z0-9._]{1,30}$"#, options: .regularExpression) != nil else { return nil }
        return sha256(name)
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// A creator code the person types, such as JANE20.
enum PromoCode {
    static func normalized(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.range(of: #"^[A-Z0-9_-]{3,30}$"#, options: .regularExpression) != nil ? code : nil
    }
}
