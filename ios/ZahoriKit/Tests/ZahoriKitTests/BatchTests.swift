import XCTest
import ZahoriCore
@testable import ZahoriKit

/// Port of the batch / recommendations logic in tests/test_api.py (offline), plus the concurrency cap
/// and cache behaviour required by the iOS brief.
final class BatchTests: XCTestCase {
    /// Summary strings and counters for the live detail fixture, compared with
    /// `_check_single_book_availability` run in Python on the same data.
    func testBatchSummaryMatchesPython() throws {
        let edition = try ParserHelper.liveDetail()
        for case let row as [String: Any] in Fixture.golden("batch", as: [Any].self) {
            var e = edition
            if row["only_loaned"] as? Bool == true { e.copies = e.copies.filter { !$0.isAvailable } }
            let success = row["success"] as! Bool
            let result = SearchResult(queryTitle: "Cien años de soledad", queryAuthor: "García Márquez",
                                      outcome: success ? .found(editions: [e], totalEditions: 3, isPartial: false)
                                                       : .catalogUnavailable(reason: "boom"))
            let proximity = Proximity(selectedLibraries: row["selected"] as! [String], radiusKm: row["radius_km"] as! Double)
            let a = Availability.summarize(result, proximity: proximity)
            let py = row["result"] as! [String: Any]
            let label = "\(row["selected"]!) success=\(success)"

            if !success {
                // Deliberate change: Python reports "No encontrado en catálogo" when the catalog fails.
                XCTAssertEqual(py["status_summary"] as? String, "No encontrado en catálogo")
                XCTAssertEqual(a.state, .catalogUnavailable, label)
                XCTAssertEqual(a.statusSummary, "Catálogo no disponible", label)
                continue
            }
            XCTAssertEqual(a.statusSummary, py["status_summary"] as? String, label)
            XCTAssertEqual(a.isAvailable, py["is_available"] as? Bool, label)
            XCTAssertEqual(a.totalEditions, py["total_editions"] as? Int, label)
            XCTAssertEqual(a.totalCopies, py["total_copies"] as? Int, label)
            XCTAssertEqual(a.totalAvailableCopies, py["total_available_copies"] as? Int, label)
            XCTAssertEqual(a.bestMatchLibrary, opt(py["best_match_library"]), label)
            XCTAssertEqual(a.bestMatchDistanceKm, opt(py["best_match_distance_km"]), label)
            XCTAssertEqual(a.directMatchesCount, py["direct_matches_count"] as? Int, label)
            XCTAssertEqual(a.directMatchesAvailable, py["direct_matches_available"] as? Int, label)
        }
    }

    func testNotFoundSummary() {
        let a = Availability.summarize(SearchResult(queryTitle: "x", queryAuthor: "", outcome: .noResults),
                                       proximity: Proximity(selectedLibraries: [], radiusKm: 5))
        XCTAssertEqual(a.state, .notInCatalog)
        XCTAssertEqual(a.statusSummary, "No encontrado en catálogo")
    }

    // MARK: Concurrency cap

    func testBatchNeverExceedsThreeConcurrentChecks() async {
        let catalog = FakeCatalog(delay: 0.05)
        let service = AvailabilityService(catalog: catalog)
        let books = (1...12).map { Book.fake("Libro \($0)") }
        let progress = Counter()
        await service.checkAll(books) { _, _ in await progress.increment() }

        let stats = await catalog.stats()
        XCTAssertEqual(stats.calls, 12)
        XCTAssertEqual(stats.maxInFlight, 3)
        let done = await progress.value
        XCTAssertEqual(done, 12)
    }

    func testLimiterHandsOverSlotsFairly() async {
        let limiter = ConcurrencyLimiter(limit: 2)
        let catalog = FakeCatalog(delay: 0.02)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<8 {
                group.addTask {
                    _ = await limiter.run { await catalog.search(title: "\(i)", author: "", maxItems: 1) }
                }
            }
        }
        let stats = await catalog.stats()
        XCTAssertEqual(stats.maxInFlight, 2)
        XCTAssertEqual(stats.calls, 8)
    }

    func testBatchSendsDoubleCleanedTitleAndLimit() async {
        let catalog = FakeCatalog()
        let book = Book(bookID: "1", title: "Sapiens: A Brief History", cleanTitle: "Sapiens", author: "Harari")
        _ = await AvailabilityService(catalog: catalog).check(book)
        let call = await catalog.lastCall
        XCTAssertEqual(call?.title, "Sapiens")
        XCTAssertEqual(call?.author, "Harari")
        XCTAssertEqual(call?.maxItems, 2)
    }

    // MARK: Recomendaciones

    func testRecommendationsStopAtTargetAndUseLimitOne() async {
        let catalog = FakeCatalog(availableTitles: ["A", "B", "C", "D", "E"])
        let books = ["A", "B", "C", "D", "E", "F", "G"].map(Book.fake)
        var rng = SeededRNG(seed: 42)
        let recs = await AvailabilityService(catalog: catalog)
            .recommendations(from: books, proximity: Proximity(selectedLibraries: [], radiusKm: 5), using: &rng)

        XCTAssertEqual(recs.count, 2)
        XCTAssert(recs.allSatisfy { ["A", "B", "C", "D", "E"].contains($0.book.title) })
        let stats = await catalog.stats()
        XCTAssertLessThanOrEqual(stats.calls, 6) // at most two chunks of 3
        XCTAssertEqual(stats.maxItems, [1])
    }

    func testRecommendationsAreDeterministicForASeed() async {
        let books = (1...9).map { Book.fake("T\($0)") }
        let catalog = FakeCatalog(availableTitles: Set(books.map(\.title)))
        let service = AvailabilityService(catalog: catalog)
        var r1 = SeededRNG(seed: 7), r2 = SeededRNG(seed: 7)
        let p = Proximity(selectedLibraries: [], radiusKm: 5)
        let a = await service.recommendations(from: books, proximity: p, using: &r1).map(\.book.title)
        let b = await service.recommendations(from: books, proximity: p, using: &r2).map(\.book.title)
        XCTAssertEqual(a, b)
    }

    func testRecommendationsWhenNothingAvailable() async {
        let catalog = FakeCatalog(availableTitles: [])
        var rng = SeededRNG(seed: 1)
        let recs = await AvailabilityService(catalog: catalog)
            .recommendations(from: (1...5).map { Book.fake("X\($0)") }, proximity: Proximity(selectedLibraries: [], radiusKm: 5), using: &rng)
        XCTAssertTrue(recs.isEmpty)
        let calls = await catalog.stats().calls
        XCTAssertEqual(calls, 5)
    }

    // MARK: Cache

    func testCacheKeepsLastGoodResultWhenCatalogIsDown() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = AvailabilityCache(url: url, now: { t0 })

        let good = SearchResult(queryTitle: "A", queryAuthor: "", outcome: .found(editions: [Edition(title: "A")], totalEditions: 1, isPartial: false))
        let down = SearchResult(queryTitle: "A", queryAuthor: "", outcome: .catalogUnavailable(reason: "x"))

        let first = await cache.record(good, for: "b1")
        XCTAssertEqual(first.result, good)
        XCTAssertNil(first.cachedAt)

        let fallback = await cache.record(down, for: "b1")
        XCTAssertEqual(fallback.result, good)
        XCTAssertEqual(fallback.cachedAt, t0)

        // Unknown book while offline: the failure is shown as-is.
        let unknown = await cache.record(down, for: "b2")
        XCTAssertEqual(unknown.result, down)
        XCTAssertNil(unknown.cachedAt)

        // Survives a relaunch.
        let reloaded = AvailabilityCache(url: url)
        let entry = await reloaded.entry(for: "b1")
        XCTAssertEqual(entry?.result, good)
        XCTAssertEqual(entry?.checkedAt, t0)
    }

    func testNoResultsReplacesCachedEntry() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = AvailabilityCache(url: url)
        _ = await cache.record(SearchResult(queryTitle: "A", queryAuthor: "", outcome: .found(editions: [Edition(title: "A")], totalEditions: 1, isPartial: false)), for: "b1")
        let now = await cache.record(SearchResult(queryTitle: "A", queryAuthor: "", outcome: .noResults), for: "b1")
        XCTAssertEqual(now.result.outcome, .noResults)
    }

    func testShelfIsCached() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let shelf = AvailabilityCache.CachedShelf(userID: "1", shelf: "to-read", userName: "Ana", books: [Book.fake("A")], fetchedAt: Date(timeIntervalSince1970: 5))
        await AvailabilityCache(url: url).saveShelf(shelf)
        let loaded = await AvailabilityCache(url: url).shelf()
        XCTAssertEqual(loaded, shelf)
    }

    func testSettingsRadiusClamp() {
        XCTAssertEqual(AppSettings.clampRadius(0), 1)
        XCTAssertEqual(AppSettings.clampRadius(7), 7)
        XCTAssertEqual(AppSettings.clampRadius(99), 20)
        XCTAssertEqual(AppSettings().radiusKm, 5)
        XCTAssertEqual(AppSettings().shelf, "to-read")
    }

    func testSettingsRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var s = AppSettings()
        s.selectedLibraryIDs = ["eugenio_trias", "jose_acuna"]
        s.radiusKm = 12
        s.goodreadsUserID = "177587843"
        let store = JSONFileStore<AppSettings>(url: url)
        try store.save(s)
        XCTAssertEqual(store.load(), s)
    }
}

// MARK: - Test doubles

extension Book {
    static func fake(_ title: String) -> Book {
        Book(bookID: "id-\(title)", title: title, cleanTitle: title, author: "Autor")
    }
}

actor Counter {
    var value = 0
    func increment() { value += 1 }
}

/// Catalog stub that records concurrency. Titles in `availableTitles` get one available copy.
actor FakeCatalog: CatalogSearching {
    private let delay: TimeInterval
    private let availableTitles: Set<String>
    private var inFlight = 0
    private var maxInFlight = 0
    private var calls = 0
    private var maxItemsSeen: Set<Int> = []
    private(set) var lastCall: (title: String, author: String, maxItems: Int)?

    init(delay: TimeInterval = 0, availableTitles: Set<String> = []) {
        self.delay = delay
        self.availableTitles = availableTitles
    }

    nonisolated func search(title: String, author: String, maxItems: Int) async -> SearchResult {
        await begin(title, author, maxItems)
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
        await end()
        let available = availableTitles.contains(title)
        let copy = Copy(library: "RETIRO. BP Eugenio Trías", location: "Sala adultos", shelfmark: "N X", itemType: "Prestable",
                        support: "Libro", statusRaw: available ? "Disponible" : "Prestado (hasta 01/01/2027)",
                        isAvailable: available, dueDate: available ? nil : "01/01/2027")
        return SearchResult(queryTitle: title, queryAuthor: author,
                            outcome: .found(editions: [Edition(title: title, copies: [copy])], totalEditions: 1, isPartial: false))
    }

    private func begin(_ t: String, _ a: String, _ m: Int) {
        calls += 1
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        maxItemsSeen.insert(m)
        lastCall = (t, a, m)
    }

    private func end() { inFlight -= 1 }

    func stats() -> (calls: Int, maxInFlight: Int, maxItems: Set<Int>) { (calls, maxInFlight, maxItemsSeen) }
}

/// SplitMix64, so recommendation shuffles are reproducible in tests.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
