import Foundation

/// Ports of the pure helpers in backend/goodreads_service.py.
public enum GoodreadsText {
    /// Port of `extract_goodreads_user_id`.
    public static func userID(from input: String) -> String {
        let s = PyText.strip(input)
        if s.isEmpty { return "" }
        if PyText.isDigits(s) { return s }
        if let m = PyText.search(#"/user/show/(\d+)"#, s, group: 1) { return m }
        if let m = PyText.search(#"/review/list(?:_rss)?/(\d+)"#, s, group: 1) { return m }
        if let m = PyText.search(#"\b(\d{5,12})\b"#, s, group: 1) { return m }
        return s
    }

    /// Port of `extract_goodreads_user_name`: RSS channel title first, then the profile URL slug.
    public static func userName(from input: String, channelTitle: String? = nil) -> String? {
        if let channelTitle,
           let name = PyText.search(#"^(.*?)(?:'s|’s)\s+bookshelf"#, PyText.strip(channelTitle), group: 1, ignoreCase: true) {
            let n = PyText.strip(name)
            if !n.isEmpty && !PyText.isDigits(n) { return n }
        }
        if !input.isEmpty,
           var slug = PyText.search(#"/user/show/\d+[-_]([a-zA-Z0-9_\-]+)"#, PyText.strip(input), group: 1) {
            slug = String(slug.split(separator: "?", omittingEmptySubsequences: false)[0])
            slug = String(slug.split(separator: "/", omittingEmptySubsequences: false)[0])
            let words = slug.split(whereSeparator: { $0 == "-" || $0 == "_" })
            let cleaned = words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    private static let seriesOrEdition =
        #"\((?:[^)]*#\d+|[^)]*(?:edition|edici[oó]n|series|saga|book|volumen|volume|trilog[íi]a|classics|collection)[^)]*)\)"#

    /// Port of `clean_book_title_for_search`.
    public static func cleanTitleForSearch(_ title: String) -> String {
        if title.isEmpty { return "" }
        var t = PyText.strip(title)
        t = PyText.sub(#"\[.*?\]"#, " ", t)
        t = PyText.sub(seriesOrEdition, " ", t, ignoreCase: true)
        t = PyText.sub(#"\([^)]*\)\s*$"#, " ", t)

        if t.contains(":") {
            let first = PyText.strip(String(t.split(separator: ":", omittingEmptySubsequences: false)[0]))
            if first.unicodeScalars.count >= 3 { t = first }
        }

        // re.sub(r"[^\w\s\-\.\'\,\¿\?\¡\!]", " ", t)
        let keep: Set<Unicode.Scalar> = ["-", ".", "'", ",", "¿", "?", "¡", "!"]
        var scalars = String.UnicodeScalarView()
        for u in t.unicodeScalars {
            scalars.append(PyText.isWordScalar(u) || u.properties.isWhitespace || keep.contains(u) ? u : " ")
        }
        return PyText.collapseWhitespace(String(scalars))
    }
}
