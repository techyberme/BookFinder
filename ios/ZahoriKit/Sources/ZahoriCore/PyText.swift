import Foundation

/// Small helpers that reproduce the Python string/regex semantics the reference implementation relies on.
/// Kept in one place so every port of a `re.sub` / `str.strip` reads the same way.
public enum PyText {
    /// `str.strip()`
    public static func strip(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `re.sub(pattern, template, s, flags)`
    public static func sub(_ pattern: String, _ template: String, _ s: String, ignoreCase: Bool = false) -> String {
        let re = regex(pattern, ignoreCase: ignoreCase)
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// `re.search(pattern, s)` returning the requested capture group (0 = whole match).
    public static func search(_ pattern: String, _ s: String, group: Int = 0, ignoreCase: Bool = false) -> String? {
        let re = regex(pattern, ignoreCase: ignoreCase)
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: group), in: s) else { return nil }
        return String(s[r])
    }

    public static func matches(_ pattern: String, _ s: String, ignoreCase: Bool = false) -> Bool {
        search(pattern, s, ignoreCase: ignoreCase) != nil
    }

    /// Python `\w` for `str` patterns: `ch.isalnum() or ch == "_"` (letters and numbers of any script).
    public static func isWordScalar(_ u: Unicode.Scalar) -> Bool {
        if u == "_" { return true }
        switch u.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    /// Python `str.isdigit()` (non-empty, every character a digit).
    public static func isDigits(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy {
            $0.properties.numericType == .decimal || $0.properties.numericType == .digit
        }
    }

    /// Python `" ".join(s.split())`
    public static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    private static func regex(_ pattern: String, ignoreCase: Bool) -> NSRegularExpression {
        let key = (ignoreCase ? "i:" : "s:") + pattern
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let re = cache[key] { return re }
        // Patterns are compile-time constants from this codebase; a bad one is a programmer error.
        let re = try! NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
        cache[key] = re
        return re
    }
}
