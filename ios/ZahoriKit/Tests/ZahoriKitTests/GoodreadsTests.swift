import XCTest
import ZahoriCore
@testable import ZahoriKit

/// Port of tests/test_goodreads.py, plus golden comparisons against the Python implementation.
final class GoodreadsTests: XCTestCase {
    // test_extract_goodreads_user_id
    func testExtractUserID() {
        XCTAssertEqual(GoodreadsText.userID(from: "177587843"), "177587843")
        XCTAssertEqual(GoodreadsText.userID(from: "https://www.goodreads.com/user/show/177587843-john-doe"), "177587843")
        XCTAssertEqual(GoodreadsText.userID(from: "https://www.goodreads.com/user/show/99887766"), "99887766")
        XCTAssertEqual(GoodreadsText.userID(from: "https://www.goodreads.com/review/list/12345678?shelf=to-read"), "12345678")
        XCTAssertEqual(GoodreadsText.userID(from: "https://www.goodreads.com/review/list_rss/12345678"), "12345678")
        for (input, expected) in Fixture.golden("user_id", as: [String: String].self) {
            XCTAssertEqual(GoodreadsText.userID(from: input), expected, input)
        }
    }

    // test_extract_goodreads_user_name
    func testExtractUserName() {
        XCTAssertEqual(GoodreadsText.userName(from: "https://www.goodreads.com/user/show/155193797-javier-bermejo"), "Javier Bermejo")
        XCTAssertEqual(GoodreadsText.userName(from: "https://www.goodreads.com/user/show/177587843-john-doe_smith"), "John Doe Smith")
        XCTAssertEqual(GoodreadsText.userName(from: "177587843", channelTitle: "Javier Bermejo's bookshelf: to-read"), "Javier Bermejo")
        XCTAssertEqual(GoodreadsText.userName(from: "177587843", channelTitle: "Ana García’s bookshelf: currently-reading"), "Ana García")
        for case let row as [Any] in Fixture.golden("user_name", as: [Any].self) {
            let name = GoodreadsText.userName(from: row[0] as! String, channelTitle: opt(row[1]))
            XCTAssertEqual(name, opt(row[2]), "\(row)")
        }
    }

    // test_clean_book_title_for_search
    func testCleanTitle() {
        XCTAssertEqual(GoodreadsText.cleanTitleForSearch("Dune (Dune Chronicles, #1)"), "Dune")
        XCTAssertEqual(GoodreadsText.cleanTitleForSearch("The Fellowship of the Ring (The Lord of the Rings, #1)"), "The Fellowship of the Ring")
        XCTAssertEqual(GoodreadsText.cleanTitleForSearch("Harry Potter and the Sorcerer's Stone (Harry Potter, #1)"), "Harry Potter and the Sorcerer's Stone")
        XCTAssertEqual(GoodreadsText.cleanTitleForSearch("Watchmen [Graphic Novel]"), "Watchmen")
        XCTAssertEqual(GoodreadsText.cleanTitleForSearch("1984 (Signet Classics)"), "1984")
        XCTAssertEqual(GoodreadsText.cleanTitleForSearch("Cien años de soledad (Edición 50 Aniversario)"), "Cien años de soledad")
        XCTAssertEqual(GoodreadsText.cleanTitleForSearch("Sapiens: A Brief History of Humankind"), "Sapiens")
        XCTAssertEqual(GoodreadsText.cleanTitleForSearch("El infinito en un junco: La invención de los libros en el mundo antiguo"), "El infinito en un junco")
        for (input, expected) in Fixture.golden("clean_title", as: [String: String].self) {
            XCTAssertEqual(GoodreadsText.cleanTitleForSearch(input), expected, input)
        }
    }

    func testParseLiveFeedFixture() throws {
        try assertFeed("goodreads_to_read.xml", userInput: "177587843", goldenKey: "rss_live")
    }

    func testParseSyntheticFeedFixture() throws {
        try assertFeed("goodreads_synthetic.xml", userInput: "https://www.goodreads.com/user/show/155193797-ana-garcia",
                       goldenKey: "rss_synthetic")
    }

    func testInvalidXMLThrows() {
        XCTAssertThrowsError(try GoodreadsRSSParser.parse(Data("<rss><channel>".utf8), userInput: "1"))
    }

    func testFeedWithoutChannelIsEmpty() throws {
        let shelf = try GoodreadsRSSParser.parse(Data("<rss version=\"2.0\"></rss>".utf8), userInput: "1")
        XCTAssertTrue(shelf.books.isEmpty)
        XCTAssertNil(shelf.userName)
    }

    private func assertFeed(_ file: String, userInput: String, goldenKey: String) throws {
        let golden = Fixture.golden(goldenKey, as: [String: Any].self)
        let shelf = try GoodreadsRSSParser.parse(Fixture.data(file), userInput: userInput)
        XCTAssertEqual(shelf.userName, opt(golden["user_name"]))
        let expected = golden["books"] as! [[String: Any]]
        XCTAssertEqual(shelf.books.count, expected.count)
        for (b, py) in zip(shelf.books, expected) {
            XCTAssertEqual(b.bookID, py["book_id"] as? String)
            XCTAssertEqual(b.title, py["title"] as? String)
            XCTAssertEqual(b.cleanTitle, py["clean_title"] as? String)
            XCTAssertEqual(b.author, py["author"] as? String)
            XCTAssertEqual(b.isbn, opt(py["isbn"]))
            XCTAssertEqual(b.coverImageURL, opt(py["cover_image_url"]))
            XCTAssertEqual(b.userRating, py["user_rating"] as? Int)
            XCTAssertEqual(b.userShelves, opt(py["user_shelves"]))
            XCTAssertEqual(b.dateAdded, opt(py["date_added"]))
            XCTAssertEqual(b.link, opt(py["link"]))
        }
    }
}
