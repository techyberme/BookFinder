import XCTest
import ZahoriCore
@testable import ZahoriKit

enum ParserHelper {
    static func liveDetail() throws -> Edition {
        try OPACParser().parseDetail(Fixture.latin1("opac_detail_cien_anos.html"), url: "DOC_URL")
    }
}

/// Port of the offline half of tests/test_scraper.py, plus golden comparisons on captured OPAC pages.
final class ScraperParsingTests: XCTestCase {
    let parser = OPACParser()
    var sampleHTML: String { Fixture.golden("sample_detail_html") }

    // test_parse_holdings_from_html
    func testParseHoldingsFromSample() throws {
        let h = try parser.parseHoldings(sampleHTML)
        XCTAssertEqual(h.count, 2)

        XCTAssertEqual(h[0].library, "CARABANCHEL. BP La Chata")
        XCTAssertEqual(h[0].location, "Sala adultos")
        XCTAssertEqual(h[0].shelfmark, "N GAR cie")
        XCTAssertEqual(h[0].barcode, "1402046226")
        XCTAssertTrue(h[0].isAvailable)
        XCTAssertNil(h[0].dueDate)

        XCTAssertEqual(h[1].library, "CHAMARTÍN. BP Dámaso Alonso")
        XCTAssertEqual(h[1].location, "Depósito")
        XCTAssertEqual(h[1].shelfmark, "N GAR cie")
        XCTAssertFalse(h[1].isAvailable)
        XCTAssertEqual(h[1].dueDate, "15/09/2026")
        XCTAssert(h[1].statusRaw.contains("Prestado"))
    }

    // test_parse_detail_page
    func testParseDetailSample() throws {
        let book = try parser.parseDetail(sampleHTML, url: "http://example.com/doc1")
        XCTAssert(book.title.contains("Cien años de soledad"))
        XCTAssert(book.author!.contains("García Márquez"))
        XCTAssertEqual(book.year, "2024")
        XCTAssertEqual(book.isbn, "978-84-663-7353-1")
        XCTAssertEqual(book.totalCopies, 2)
        XCTAssertEqual(book.availableCopies, 1)
        assertEdition(book, Fixture.golden("detail_sample"))
    }

    func testParseLiveDetailMatchesPython() throws {
        let edition = try ParserHelper.liveDetail()
        XCTAssertEqual(edition.copies.count, 10)
        assertEdition(edition, Fixture.golden("detail_live"))
    }

    func testParseListPagesMatchPython() throws {
        let base = URL(string: Fixture.golden("list_base_url", as: String.self))!
        for (file, rows) in Fixture.golden("list_pages", as: [String: [[Any]]].self) {
            let entries = try parser.parseList(Fixture.latin1(file), baseURL: base)
            XCTAssertEqual(entries.count, rows.count, file)
            for (e, row) in zip(entries, rows) {
                let meta = row[0] as! [String: String]
                XCTAssertEqual(e.title, meta["title"], file)
                XCTAssertEqual(e.author, meta["author"], file)
                XCTAssertEqual(e.publication, meta["publication"], file)
                XCTAssertEqual(e.detailURL.absoluteString, row[1] as? String, file)
            }
        }
    }

    func testClassifiesCapturedPages() throws {
        XCTAssertEqual(try parser.classify(Fixture.latin1("opac_list_cien_anos.html")), .resultList)
        XCTAssertEqual(try parser.classify(Fixture.latin1("opac_author_rowling.html")), .resultList)
        XCTAssertEqual(try parser.classify(Fixture.latin1("opac_single_result.html")), .resultList)
        XCTAssertEqual(try parser.classify(Fixture.latin1("opac_detail_cien_anos.html")), .singleRecord)
        XCTAssertEqual(try parser.classify(Fixture.latin1("opac_no_results.html")), .noResults)
        XCTAssertEqual(try parser.classify(sampleHTML), .singleRecord)
        XCTAssertEqual(try parser.classify("<html><body><h1>Mantenimiento</h1></body></html>"), .unrecognized)
    }

    func testSessionHandshakePages() {
        let redirect = parser.sessionRedirect(Fixture.latin1("opac_session_entry.html"))
        XCTAssertNotNil(redirect)
        XCTAssert(redirect!.hasPrefix("/biblio_publicas/cgi-bin/abnetopac/"))
        XCTAssert(redirect!.hasSuffix("?ACC=101"))
        XCTAssertNotNil(parser.formAction(Fixture.latin1("opac_advanced_form.html")))
        XCTAssertNil(parser.sessionRedirect("<html><body>sin redirección</body></html>"))
    }

    func testLoanStatusRules() {
        XCTAssertEqual(OPACParser.loanStatus("Disponible").isAvailable, true)
        let loaned = OPACParser.loanStatus("Disponible después de 15/09/2026")
        XCTAssertEqual(loaned.text, "Prestado (hasta 15/09/2026)")
        XCTAssertEqual(loaned.dueDate, "15/09/2026")
        XCTAssertEqual(OPACParser.loanStatus("No disponible Nº de reservas: 1").text, "No disponible Nº de reservas: 1")
        XCTAssertEqual(OPACParser.loanStatus("").text, "No disponible")
        XCTAssertFalse(OPACParser.loanStatus("Prestado hasta 01/01/2027").isAvailable)
    }

    /// Partial markup (accordion without a table, rows with < 4 cells) is skipped, never a crash.
    func testPartialMarkupIsSkipped() throws {
        let html = """
        <div class="c-accordion_item"><button class="c-accordion_btn">Sucursal: RETIRO. BP Eugenio Trías</button></div>
        <div class="c-accordion_item"><button class="c-accordion_btn"></button>
          <table><tr><td>a</td><td>b</td></tr>
          <tr><td>N ABC xyz</td><td></td><td></td><td>Disponible</td></tr>
          <tr><td>Sala N GAR 12</td><td></td><td></td><td>Disponible</td></tr></table></div>
        """
        let copies = try parser.parseHoldings(html)
        // Expected values come from running the same HTML through backend/scraper.py.
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(copies[0].library, "Biblioteca Central / Red de Bibliotecas")
        XCTAssertEqual(copies[0].shelfmark, "N/A")
        XCTAssertEqual(copies[1].shelfmark, "N GAR 12")
        XCTAssertEqual(copies[0].itemType, "Prestable")
        XCTAssertEqual(copies[0].support, "Libro")
        XCTAssertEqual(copies[0].location, "General")
    }
}
