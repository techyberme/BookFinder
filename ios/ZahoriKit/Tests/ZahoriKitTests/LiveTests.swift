import XCTest
import ZahoriCore
@testable import ZahoriKit

/// Live tests against the real OPAC and Goodreads (ports of the `test_live_*` cases).
/// Opt-in so CI stays deterministic:  ZAHORI_LIVE_TESTS=1 swift test --filter LiveTests
final class LiveTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ZAHORI_LIVE_TESTS"] == "1",
                          "Set ZAHORI_LIVE_TESTS=1 to run live network tests")
    }

    let opac = OPACClient(timeout: 25)

    // test_live_search_cien_anos
    func testLiveSearchCienAnos() async {
        let r = await opac.search(title: "Cien años de soledad", author: "García Márquez", maxItems: 2)
        guard case .found = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertGreaterThan(r.totalEditions, 0)
        let first = r.editions[0]
        XCTAssert(first.title.contains("Cien años de soledad"))
        XCTAssertFalse(first.copies.isEmpty)
        XCTAssert(first.copies.contains(where: \.isAvailable))
    }

    // test_live_search_no_results
    func testLiveSearchNoResults() async {
        let r = await opac.search(title: "xkqw7899zznonexistenttitle9999", author: "", maxItems: 2)
        XCTAssertEqual(r.outcome, .noResults)
    }

    // test_live_search_author_only
    func testLiveSearchAuthorOnly() async {
        let r = await opac.search(title: "", author: "J.K. Rowling", maxItems: 2)
        guard case .found = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssert(r.editions.contains { ($0.author ?? "").contains("Rowling") })
    }

    // test_search_live_api_with_geo_filters
    func testLiveSearchWithGeoFilters() async {
        let r = await opac.search(title: "Ficciones", author: "Borges", maxItems: 1)
        guard case .found = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssert(r.editions[0].title.contains("Ficciones"))
        let g = Proximity(selectedLibraries: ["eugenio_trias"], radiusKm: 5).group(r.editions[0].copies)
        XCTAssertEqual(g.direct.count + g.nearby.count + g.other.count, r.editions[0].copies.count)
    }

    // test_live_goodreads_shelf_fetch
    func testLiveGoodreadsShelf() async throws {
        do {
            let shelf = try await GoodreadsClient().fetchShelf(userInput: "177587843", shelf: "to-read")
            if let b = shelf.books.first {
                XCTAssertFalse(b.title.isEmpty)
                XCTAssertFalse(b.cleanTitle.isEmpty)
            }
        } catch {
            throw XCTSkip("Goodreads unreachable or rate limited: \(error)")
        }
    }

    // test_batch_availability_api / test_recommendations_endpoint
    func testLiveBatchAndRecommendations() async {
        let service = AvailabilityService(catalog: opac)
        let books = [
            Book(bookID: "b1", title: "Cien años de soledad", cleanTitle: "Cien años de soledad", author: "García Márquez"),
            Book(bookID: "b2", title: "Ficciones", cleanTitle: "Ficciones", author: "Borges"),
            Book(bookID: "b3", title: "El Quijote", cleanTitle: "El Quijote", author: "Cervantes"),
        ]
        let counter = Counter()
        await service.checkAll(Array(books.prefix(2)), limitPerBook: 1) { _, _ in await counter.increment() }
        let checked = await counter.value
        XCTAssertEqual(checked, 2)

        var rng = SystemRandomNumberGenerator()
        let recs = await service.recommendations(from: books, proximity: Proximity(selectedLibraries: ["eugenio_trias"], radiusKm: 5), using: &rng)
        XCTAssertGreaterThanOrEqual(recs.count, 1)
    }
}
