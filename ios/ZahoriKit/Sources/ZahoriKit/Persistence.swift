import Foundation
import ZahoriCore

/// A Codable value stored as one JSON file (Application Support by default). Writes are atomic.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(filename: String, directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zahori", isDirectory: true)
        self.url = dir.appendingPathComponent(filename)
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.zahori.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.zahori.encode(value).write(to: url, options: .atomic)
    }

    public func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

extension JSONEncoder {
    static let zahori: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let zahori: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// User settings. The web app keeps only the Goodreads fields (localStorage); libraries and radius
/// are persisted here as the iOS brief requires.
public struct AppSettings: Codable, Equatable, Sendable {
    public static let radiusRange = 1...20
    /// Default of the web slider (`value="5"`), which wins over the API default of 3 km.
    public static let defaultRadius = 5

    public var selectedLibraryIDs: [String] = []
    public var radiusKm: Int = AppSettings.defaultRadius
    public var goodreadsUserID: String?
    public var goodreadsUserName: String?
    public var shelf: String = "to-read"
    /// Local notifications before each loan's due date.
    public var loanRemindersEnabled = true
    public var reminderDaysBefore = 2

    public static let reminderDaysRange = 1...7

    public init() {}

    /// Missing keys fall back to defaults, so settings saved by older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        selectedLibraryIDs = try c.decodeIfPresent([String].self, forKey: .selectedLibraryIDs) ?? d.selectedLibraryIDs
        radiusKm = try c.decodeIfPresent(Int.self, forKey: .radiusKm) ?? d.radiusKm
        goodreadsUserID = try c.decodeIfPresent(String.self, forKey: .goodreadsUserID)
        goodreadsUserName = try c.decodeIfPresent(String.self, forKey: .goodreadsUserName)
        shelf = try c.decodeIfPresent(String.self, forKey: .shelf) ?? d.shelf
        loanRemindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .loanRemindersEnabled) ?? d.loanRemindersEnabled
        reminderDaysBefore = try c.decodeIfPresent(Int.self, forKey: .reminderDaysBefore) ?? d.reminderDaysBefore
    }

    /// Port of the slider/number-field sync in frontend/app.js: clamp to 1...20.
    public static func clampRadius(_ value: Int) -> Int {
        min(max(value, radiusRange.lowerBound), radiusRange.upperBound)
    }
}

/// Last successful loans download, shown with "actualizado hace X" when the OPAC is unreachable.
public struct CachedLoans: Codable, Equatable, Sendable {
    public var loans: [Loan]
    public var fetchedAt: Date

    public init(loans: [Loan], fetchedAt: Date) {
        self.loans = loans
        self.fetchedAt = fetchedAt
    }
}

/// Last successful availability result per book, with timestamps, for offline display.
public actor AvailabilityCache {
    public struct Entry: Codable, Equatable, Sendable {
        public var result: SearchResult
        public var checkedAt: Date
    }

    private struct Snapshot: Codable {
        var entries: [String: Entry]
        var shelf: CachedShelf?
    }

    public struct CachedShelf: Codable, Equatable, Sendable {
        public var userID: String
        public var shelf: String
        public var userName: String?
        public var books: [Book]
        public var fetchedAt: Date

        public init(userID: String, shelf: String, userName: String?, books: [Book], fetchedAt: Date) {
            self.userID = userID
            self.shelf = shelf
            self.userName = userName
            self.books = books
            self.fetchedAt = fetchedAt
        }
    }

    private let store: JSONFileStore<Snapshot>
    private var snapshot: Snapshot
    private let now: @Sendable () -> Date

    public init(url: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = JSONFileStore(url: url)
        self.snapshot = store.load() ?? Snapshot(entries: [:], shelf: nil)
        self.now = now
    }

    public static func defaultURL() -> URL {
        JSONFileStore<Data>(filename: "availability-cache.json").url
    }

    /// What to show for a fresh `result`:
    /// - a successful answer (found / no results) replaces the cache and is returned as-is;
    /// - "catalog unavailable" falls back to the last good entry, if any, returned with its date.
    public func record(_ result: SearchResult, for bookID: String) -> (result: SearchResult, cachedAt: Date?) {
        switch result.outcome {
        case .found, .noResults:
            snapshot.entries[bookID] = Entry(result: result, checkedAt: now())
            persist()
            return (result, nil)
        case .catalogUnavailable, .invalidQuery:
            if let cached = snapshot.entries[bookID] { return (cached.result, cached.checkedAt) }
            return (result, nil)
        }
    }

    public func entry(for bookID: String) -> Entry? { snapshot.entries[bookID] }

    public func allEntries() -> [String: Entry] { snapshot.entries }

    public func saveShelf(_ shelf: CachedShelf) {
        snapshot.shelf = shelf
        persist()
    }

    public func shelf() -> CachedShelf? { snapshot.shelf }

    public func clear() {
        snapshot = Snapshot(entries: [:], shelf: nil)
        store.delete()
    }

    private func persist() {
        try? store.save(snapshot)
    }
}
