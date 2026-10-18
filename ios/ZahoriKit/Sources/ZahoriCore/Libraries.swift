import Foundation

/// A branch of the Madrid library network. Data is a verbatim export of
/// `MADRID_LIBRARIES_DB` (backend/madrid_libraries_geo.py) via ios/Scripts/make_golden.py.
public struct Library: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var lat: Double
    public var lon: Double
    public var district: String
    public var municipality: String
    public var address: String

    public var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
}

/// Lookup over the master library list. Port of `find_library_geo` / `get_all_libraries_list`.
public struct LibraryDirectory: Sendable {
    /// Libraries in the same order as the Python dict (lookup order matters for ambiguous names).
    public let libraries: [Library]
    private let byID: [String: Library]
    private let normalizedAliases: [(library: Library, aliases: [String])]

    public static let shared: LibraryDirectory = {
        guard let url = Bundle.module.url(forResource: "libraries", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let libs = try? JSONDecoder().decode([Library].self, from: data) else {
            fatalError("libraries.json missing from ZahoriCore resources")
        }
        return LibraryDirectory(libraries: libs)
    }()

    public init(libraries: [Library]) {
        self.libraries = libraries
        self.byID = Dictionary(libraries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.normalizedAliases = libraries.map { ($0, $0.aliases.map(LibraryDirectory.normalize)) }
    }

    public func library(id: String) -> Library? { byID[id] }

    /// Sorted by (municipality, district, name), like `get_all_libraries_list`.
    public var sortedList: [Library] {
        libraries.sorted { ($0.municipality, $0.district, $0.name) < ($1.municipality, $1.district, $1.name) }
    }

    /// Port of `normalize_text`: strip accents, keep ASCII alphanumerics, lowercase, collapse spaces.
    public static func normalize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var out = String.UnicodeScalarView()
        for u in text.decomposedStringWithCompatibilityMapping.unicodeScalars {
            if u.properties.canonicalCombiningClass != .notReordered { continue }
            if u.isASCII, u.properties.isAlphabetic || ("0"..."9").contains(u) {
                out.append(u)
            } else {
                // Whitespace and every other character become a space, as in re.sub(r"[^a-zA-Z0-9\s]", " ")
                out.append(" ")
            }
        }
        return PyText.collapseWhitespace(String(out).lowercased())
    }

    private static let stopTokens: Set<String> = [
        "bp", "biblioteca", "publica", "municipal", "de", "la", "el", "los", "las", "y", "del", "en", "dña", "don",
    ]

    /// Port of `find_library_geo`: exact alias, then substring containment, then >= 2 shared tokens.
    public func find(_ rawName: String) -> Library? {
        guard !rawName.isEmpty else { return nil }
        let norm = Self.normalize(rawName)

        for entry in normalizedAliases where entry.aliases.contains(norm) {
            return entry.library
        }
        for entry in normalizedAliases {
            for alias in entry.aliases where alias.contains(norm) || norm.contains(alias) {
                return entry.library
            }
        }

        let normTokens = Set(norm.split(separator: " ").map(String.init)).subtracting(Self.stopTokens)
        var best: Library?
        var maxOverlap = 0
        for entry in normalizedAliases {
            for alias in entry.aliases {
                let aliasTokens = Set(alias.split(separator: " ").map(String.init)).subtracting(Self.stopTokens)
                let overlap = normTokens.intersection(aliasTokens).count
                if overlap > maxOverlap && overlap >= 2 {
                    maxOverlap = overlap
                    best = entry.library
                }
            }
        }
        return best
    }
}
