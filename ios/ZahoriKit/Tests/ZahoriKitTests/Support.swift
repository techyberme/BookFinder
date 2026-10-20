import Foundation
import XCTest
import ZahoriCore

/// Loads saved fixtures and the Python-generated golden expectations (ios/Scripts/make_golden.py).
enum Fixture {
    static func url(_ name: String) -> URL {
        let base = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        return base.appendingPathComponent(name)
    }

    static func data(_ name: String) -> Data {
        try! Data(contentsOf: url(name))
    }

    /// OPAC pages are ISO-8859-1, like the live site.
    static func latin1(_ name: String) -> String {
        String(data: data(name), encoding: .isoLatin1)!
    }

    static let golden: [String: Any] = {
        try! JSONSerialization.jsonObject(with: data("golden.json")) as! [String: Any]
    }()

    static func golden<T>(_ key: String, as: T.Type = T.self) -> T {
        golden[key] as! T
    }
}

/// JSON null / absent → nil, otherwise the value.
func opt<T>(_ any: Any?) -> T? {
    if any is NSNull { return nil }
    return any as? T
}

/// Compares a Swift `Copy` with a Python `HoldingItem.model_dump()`.
func assertCopy(_ c: Copy, _ py: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(c.library, py["library"] as? String, file: file, line: line)
    XCTAssertEqual(c.location, py["location"] as? String, file: file, line: line)
    XCTAssertEqual(c.shelfmark, py["shelfmark"] as? String, file: file, line: line)
    XCTAssertEqual(c.barcode, opt(py["barcode"]), file: file, line: line)
    XCTAssertEqual(c.itemType, py["item_type"] as? String, file: file, line: line)
    XCTAssertEqual(c.support, py["support"] as? String, file: file, line: line)
    XCTAssertEqual(c.statusRaw, py["status_raw"] as? String, file: file, line: line)
    XCTAssertEqual(c.isAvailable, py["is_available"] as? Bool, file: file, line: line)
    XCTAssertEqual(c.dueDate, opt(py["due_date"]), file: file, line: line)
    XCTAssertEqual(c.lat, opt(py["lat"]), file: file, line: line)
    XCTAssertEqual(c.lon, opt(py["lon"]), file: file, line: line)
    XCTAssertEqual(c.district, opt(py["district"]), file: file, line: line)
    XCTAssertEqual(c.municipality, opt(py["municipality"]), file: file, line: line)
}

/// Same, plus the proximity annotations.
func assertGroupedCopy(_ c: Copy, _ py: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
    assertCopy(c, py, file: file, line: line)
    XCTAssertEqual(c.distanceKm, opt(py["distance_km"]), file: file, line: line)
    XCTAssertEqual(c.relativeToLibrary, opt(py["relative_to_library"]), file: file, line: line)
    XCTAssertEqual(c.isDirectMatch, py["is_direct_match"] as? Bool, file: file, line: line)
}

func assertEdition(_ e: Edition, _ py: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(e.title, py["title"] as? String, file: file, line: line)
    XCTAssertEqual(e.author, opt(py["author"]), file: file, line: line)
    XCTAssertEqual(e.publication, opt(py["publication"]), file: file, line: line)
    XCTAssertEqual(e.year, opt(py["year"]), file: file, line: line)
    XCTAssertEqual(e.edition, opt(py["edition"]), file: file, line: line)
    XCTAssertEqual(e.isbn, opt(py["isbn"]), file: file, line: line)
    XCTAssertEqual(e.description, opt(py["description"]), file: file, line: line)
    XCTAssertEqual(e.detailURL, opt(py["detail_url"]), file: file, line: line)
    XCTAssertEqual(e.totalCopies, py["total_copies"] as? Int, file: file, line: line)
    XCTAssertEqual(e.availableCopies, py["available_copies"] as? Int, file: file, line: line)
    let holdings = py["holdings"] as! [[String: Any]]
    XCTAssertEqual(e.copies.count, holdings.count, file: file, line: line)
    for (c, h) in zip(e.copies, holdings) { assertCopy(c, h, file: file, line: line) }
}
