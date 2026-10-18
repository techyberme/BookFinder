import XCTest
import ZahoriCore
@testable import ZahoriKit

/// The OPAC session/search flow and the Goodreads client, driven entirely by saved fixtures.
final class NetworkFlowTests: XCTestCase {
    let opac = OPACClient(timeout: 5, protocolClasses: [MockURLProtocol.self])
    let goodreads = GoodreadsClient(timeout: 5, protocolClasses: [MockURLProtocol.self])

    func testFormEncodingMatchesHttpx() {
        let body = HTTPClient.formEncode(OPACClient.payload(title: "Cien años de soledad", author: "García Márquez"))
        // Output of httpx.Request("POST", url, data=payload).content for the same dict.
        XCTAssertEqual(body, "ACC=131&START=1&FORM=2&xsqf01=&subcat=%2F&xsnf12=0&xsqf12=Cien+a%C3%B1os+de+soledad&xsqf03=Garc%C3%ADa+M%C3%A1rquez&xsnlis=10&xssort=55088864")
    }

    func testQueryCleaning() {
        XCTAssertEqual(OPACClient.cleanQuery(title: "  Cien   años ", author: "J.K. Rowling").title, "Cien años")
        XCTAssertEqual(OPACClient.cleanQuery(title: "", author: "J.K.  Rowling").author, "J K Rowling")
        let authorOnly = Dictionary(uniqueKeysWithValues: OPACClient.payload(title: "", author: "J K Rowling"))
        XCTAssertEqual(authorOnly["xsnf12"], "4")
        XCTAssertEqual(authorOnly["xsqf12"], "J K Rowling")
        XCTAssertEqual(authorOnly["xsqf03"], "J K Rowling")
        let titleOnly = Dictionary(uniqueKeysWithValues: OPACClient.payload(title: "Ficciones", author: ""))
        XCTAssertEqual(titleOnly["xsnf12"], "0")
        XCTAssertEqual(titleOnly["xsqf03"], "")
    }

    func testHandshakeThenListThenDetails() async {
        MockURLProtocol.install(OPACRoutes.handler(search: { _ in .fixture("opac_list_cien_anos.html") }))
        let result = await opac.search(title: "Cien años de soledad", author: "García Márquez", maxItems: 2)

        guard case let .found(editions, total, partial) = result.outcome else { return XCTFail("\(result.outcome)") }
        XCTAssertEqual(total, 10)
        XCTAssertEqual(editions.count, 2)
        XCTAssertFalse(partial)
        XCTAssertEqual(editions[0].copies.count, 10)

        let reqs = MockURLProtocol.requests
        // ACC=101 entry → session home → ACC=120 form → POST → 2 detail pages
        XCTAssertEqual(reqs.count, 6)
        XCTAssert(reqs[0].url.absoluteString.hasSuffix("abnetopac?ACC=101"))
        XCTAssert(reqs[1].url.path.contains("/abnetopac/"))
        XCTAssertEqual(reqs[2].url.query, "ACC=120&FORM=2")
        XCTAssertEqual(reqs[3].method, "POST")
        XCTAssert(reqs[3].body!.contains("xsqf12=Cien+a%C3%B1os+de+soledad"))
        XCTAssert(reqs[4...].allSatisfy { $0.url.query!.contains("ACC=165") })
    }

    func testSingleRecordGoesStraightToDetail() async {
        MockURLProtocol.install(OPACRoutes.handler(search: { _ in .fixture("opac_detail_cien_anos.html") }))
        let result = await opac.search(title: "Cien años de soledad", author: "", maxItems: 5)
        guard case let .found(editions, total, _) = result.outcome else { return XCTFail("\(result.outcome)") }
        XCTAssertEqual(total, 1)
        XCTAssertEqual(editions.first?.copies.count, 10)
    }

    func testNoResults() async {
        MockURLProtocol.install(OPACRoutes.handler(search: { _ in .fixture("opac_no_results.html") }))
        let result = await opac.search(title: "xkqw7899zznonexistenttitle9999", author: "", maxItems: 2)
        XCTAssertEqual(result.outcome, .noResults)
        XCTAssertEqual(result.totalEditions, 0)
    }

    func testEmptyQueryIsInvalid() async {
        let result = await opac.search(title: "  ", author: "", maxItems: 2)
        XCTAssertEqual(result.outcome, .invalidQuery)
    }

    func testAuthorOnlyFallsBackToKeywordSearch() async {
        MockURLProtocol.install(OPACRoutes.handler(search: { body in
            body.contains("xsqf01=J+K+Rowling") ? .fixture("opac_author_rowling.html") : .fixture("opac_no_results.html")
        }))
        let result = await opac.search(title: "", author: "J.K. Rowling", maxItems: 1)
        guard case .found = result.outcome else { return XCTFail("\(result.outcome)") }
        let posts = MockURLProtocol.requests.filter { $0.method == "POST" }
        XCTAssertEqual(posts.count, 2)
        XCTAssert(posts[0].body!.contains("xsnf12=4"))
        XCTAssertFalse(posts[1].body!.contains("xsnf12"))
    }

    // MARK: Catalog unavailable — never reported as "not found"

    func testOfflineIsCatalogUnavailable() async {
        MockURLProtocol.install { _, _ in .failure(.notConnectedToInternet) }
        let result = await opac.search(title: "Ficciones", author: "Borges", maxItems: 1)
        guard case let .catalogUnavailable(reason) = result.outcome else { return XCTFail("\(result.outcome)") }
        XCTAssert(reason.contains("Sin conexión"))
        let summary = Availability.summarize(result, proximity: Proximity(selectedLibraries: [], radiusKm: 5))
        XCTAssertEqual(summary.state, .catalogUnavailable)
    }

    func testHandshakeWithoutRedirectIsCatalogUnavailable() async {
        MockURLProtocol.install(OPACRoutes.handler(entry: .html("<html><body>Mantenimiento</body></html>"),
                                                   search: { _ in .fixture("opac_list_cien_anos.html") }))
        let result = await opac.search(title: "Ficciones", author: "", maxItems: 1)
        guard case .catalogUnavailable = result.outcome else { return XCTFail("\(result.outcome)") }
    }

    func testServerErrorOnSearchIsCatalogUnavailable() async {
        MockURLProtocol.install(OPACRoutes.handler(search: { _ in .html("error", status: 500) }))
        let result = await opac.search(title: "Ficciones", author: "", maxItems: 1)
        guard case .catalogUnavailable = result.outcome else { return XCTFail("\(result.outcome)") }
    }

    func testUnrecognizedMarkupIsCatalogUnavailable() async {
        MockURLProtocol.install(OPACRoutes.handler(search: { _ in .html("<html><body><div class='nuevo-diseno'>Resultados</div></body></html>") }))
        let result = await opac.search(title: "Ficciones", author: "", maxItems: 1)
        guard case .catalogUnavailable = result.outcome else { return XCTFail("\(result.outcome)") }
    }

    func testAllDetailPagesFailingIsCatalogUnavailable() async {
        MockURLProtocol.install(OPACRoutes.handler(search: { _ in .fixture("opac_list_cien_anos.html") },
                                                   detail: { _ in .html("", status: 503) }))
        let result = await opac.search(title: "Cien años", author: "", maxItems: 2)
        guard case .catalogUnavailable = result.outcome else { return XCTFail("\(result.outcome)") }
    }

    func testSomeDetailPagesFailingIsPartial() async {
        MockURLProtocol.install(OPACRoutes.handler(search: { _ in .fixture("opac_list_cien_anos.html") },
                                                   detail: { url in url.query!.contains("DOC=2") ? .html("", status: 500) : .fixture("opac_detail_cien_anos.html") }))
        let result = await opac.search(title: "Cien años", author: "", maxItems: 2)
        guard case let .found(editions, _, partial) = result.outcome else { return XCTFail("\(result.outcome)") }
        XCTAssertTrue(partial)
        XCTAssertEqual(editions.count, 2)
        XCTAssertTrue(editions[1].copies.isEmpty) // placeholder, as in Python's fetch_item_detail
        XCTAssertFalse(editions[1].title.isEmpty)
    }

    func testGetIsRetriedOnceOnTransientFailure() async throws {
        var calls = 0
        MockURLProtocol.install { _, _ in
            calls += 1
            return calls == 1 ? .failure(.timedOut) : .html("ok")
        }
        let http = HTTPClient(options: .init(timeout: 5, headers: [:], retryDelay: 0, protocolClasses: [MockURLProtocol.self]))
        let response = try await http.get(URL(string: "https://example.com/")!)
        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(calls, 2)
    }

    func testLatin1Decoding() async throws {
        MockURLProtocol.install { _, _ in .html("<p>Depósito · Año</p>") }
        let http = HTTPClient(options: .init(timeout: 5, headers: [:], protocolClasses: [MockURLProtocol.self]))
        let response = try await http.get(URL(string: "https://example.com/")!)
        XCTAssertEqual(response.text, "<p>Depósito · Año</p>")
    }

    // MARK: Goodreads

    func testGoodreadsShelf() async throws {
        MockURLProtocol.install { req, _ in
            XCTAssertEqual(req.url!.absoluteString, "https://www.goodreads.com/review/list_rss/155193797?shelf=currently-reading")
            return MockURLProtocol.Reply(body: Fixture.data("goodreads_synthetic.xml"), contentType: "application/xml")
        }
        let shelf = try await goodreads.fetchShelf(userInput: "https://www.goodreads.com/user/show/155193797-ana-garcia",
                                                   shelf: "currently-reading")
        XCTAssertEqual(shelf.userID, "155193797")
        XCTAssertEqual(shelf.userName, "Ana García")
        XCTAssertEqual(shelf.books.count, 5)
    }

    func testGoodreads404() async {
        MockURLProtocol.install { _, _ in .html("", status: 404) }
        do {
            _ = try await goodreads.fetchShelf(userInput: "123456", shelf: "to-read")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? GoodreadsClient.FetchError, .notFound(shelf: "to-read", userID: "123456"))
            XCTAssert(error.localizedDescription.contains("Asegúrese de que el perfil sea público"))
        }
    }

    func testGoodreadsOtherHTTPError() async {
        MockURLProtocol.install { _, _ in .html("", status: 503) }
        do {
            _ = try await goodreads.fetchShelf(userInput: "123456")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? GoodreadsClient.FetchError, .http(503))
        }
    }

    func testGoodreadsInvalidUser() async {
        do {
            _ = try await goodreads.fetchShelf(userInput: "   ")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? GoodreadsClient.FetchError, .invalidUser)
        }
    }
}
