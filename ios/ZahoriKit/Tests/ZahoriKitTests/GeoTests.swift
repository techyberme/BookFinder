import XCTest
@testable import ZahoriCore

/// Port of tests/test_geo.py, plus golden comparisons against the Python implementation.
final class GeoTests: XCTestCase {
    let dir = LibraryDirectory.shared

    // test_haversine_distance
    func testHaversineDistance() {
        let d = Geo.haversineKm(40.4168, -3.7038, 40.4158, -3.6791)
        XCTAssert((1.9...2.3).contains(d))
        XCTAssertEqual(Geo.haversineKm(40.4358, -3.6667, 40.4358, -3.6667), 0.0)
    }

    func testHaversineMatchesPythonForEveryLibrary() {
        for row in Fixture.golden("haversine", as: [[Double]].self) {
            XCTAssertEqual(Geo.haversineKm(row[0], row[1], row[2], row[3]), row[4], "\(row)")
        }
    }

    // test_find_library_geo
    func testFindLibraryGeo() {
        XCTAssertEqual(dir.find("CARABANCHEL. BP La Chata")?.id, "la_chata")
        XCTAssertEqual(dir.find("CARABANCHEL. BP La Chata")?.district, "Carabanchel")
        XCTAssertEqual(dir.find("José Luis Sampedro")?.id, "jose_luis_sampedro")
        XCTAssertEqual(dir.find("José Luis Sampedro")?.district, "Chamberí")
        XCTAssertEqual(dir.find("RETIRO. BP Eugenio Trías")?.id, "eugenio_trias")
        XCTAssertEqual(dir.find("CHAMARTÍN. BP Dámaso Alonso")?.id, "damaso_alonso")
        XCTAssertEqual(dir.find("MONCLOA-ARAVACA. BP Acuña")?.id, "jose_acuna")
        XCTAssertEqual(dir.find("MONCLOA-ARAVACA. BP Acuña")?.district, "Moncloa-Aravaca")
        XCTAssertEqual(dir.find("Biblioteca Pública José Acuña")?.id, "jose_acuna")
    }

    func testFindLibraryGeoMatchesPython() {
        for (name, id) in Fixture.golden("find_library_geo", as: [String: Any].self) {
            XCTAssertEqual(dir.find(name)?.id, opt(id), name)
        }
    }

    func testNormalizeMatchesPython() {
        for (input, expected) in Fixture.golden("normalize", as: [String: String].self) {
            XCTAssertEqual(LibraryDirectory.normalize(input), expected, input)
        }
    }

    // test_get_all_libraries_list
    func testAllLibrariesList() {
        let libs = dir.sortedList
        XCTAssertGreaterThanOrEqual(libs.count, 20)
        XCTAssert(libs.contains { $0.id == "eugenio_trias" })
        XCTAssertEqual(libs.map(\.id), Fixture.golden("libraries_list_ids", as: [String].self))
    }

    func testCoordinatesAreTheReferenceData() {
        let py = Fixture.golden("eugenio_trias", as: [String: Any].self)
        let lib = dir.library(id: "eugenio_trias")!
        XCTAssertEqual(lib.lat, py["lat"] as? Double)
        XCTAssertEqual(lib.lon, py["lon"] as? Double)
        XCTAssertEqual(lib.name, py["name"] as? String)
    }

    // test_apply_geospatial_grouping
    func testApplyGeospatialGrouping() {
        func copy(_ lib: String, _ avail: Bool, _ lat: Double, _ lon: Double) -> Copy {
            Copy(library: lib, location: "Sala adultos", shelfmark: "N TEST", itemType: "Prestable", support: "Libro",
                 statusRaw: avail ? "Disponible" : "Prestado (hasta 10/09/2026)", isAvailable: avail, lat: lat, lon: lon)
        }
        let copies = [
            copy("RETIRO. BP Eugenio Trías", false, 40.4158, -3.6791),
            copy("SALAMANCA. BP Manuel Alvar", true, 40.4358, -3.6667),
            copy("Biblioteca Municipal de Alcorcón", true, 40.3478, -3.8291),
        ]
        let g = Proximity(selectedLibraries: ["eugenio_trias"], radiusKm: 5).group(copies)

        XCTAssertEqual(g.direct.count, 1)
        XCTAssert(g.direct[0].library.contains("Eugenio"))
        XCTAssertTrue(g.direct[0].isDirectMatch)

        XCTAssertEqual(g.nearby.count, 1)
        XCTAssert(g.nearby[0].library.contains("Manuel Alvar"))
        XCTAssertLessThan(g.nearby[0].distanceKm!, 5)

        XCTAssertEqual(g.other.count, 1)
        XCTAssert(g.other[0].library.contains("Alcorcón"))
    }

    /// Grouping of the live detail fixture for several selections, compared copy by copy with Python.
    func testGroupingMatchesPython() throws {
        let edition = try ParserHelper.liveDetail()
        for case let g as [String: Any] in Fixture.golden("grouping", as: [Any].self) {
            let selected = g["selected"] as! [String]
            let radius = g["radius_km"] as! Double
            let result = Proximity(selectedLibraries: selected, radiusKm: radius).group(edition.copies)
            for (key, actual) in [("direct", result.direct), ("nearby", result.nearby), ("other", result.other)] {
                let expected = g[key] as! [[String: Any]]
                XCTAssertEqual(actual.count, expected.count, "\(selected) \(radius) \(key)")
                for (c, py) in zip(actual, expected) { assertGroupedCopy(c, py) }
            }
        }
    }

    // New behaviour (location fallback): no selection + origin → distances from the origin.
    func testFallbackOriginWhenNothingSelected() throws {
        let edition = try ParserHelper.liveDetail()
        let origin = Proximity.ReferencePoint(name: "tu ubicación", coordinate: .madridCenter)
        let g = Proximity(selectedLibraries: [], radiusKm: 3, fallbackOrigin: origin).group(edition.copies)
        XCTAssertTrue(g.direct.isEmpty)
        XCTAssertFalse(g.nearby.isEmpty)
        XCTAssert(g.nearby.allSatisfy { $0.relativeToLibrary == "tu ubicación" && $0.distanceKm! <= 3 })
        XCTAssertEqual(g.nearby.map(\.distanceKm!), g.nearby.map(\.distanceKm!).sorted())
        XCTAssertEqual(g.direct.count + g.nearby.count + g.other.count, edition.copies.count)
        // Selection wins over the fallback origin: identical to Python's grouping.
        let withSel = Proximity(selectedLibraries: ["eugenio_trias"], radiusKm: 5, fallbackOrigin: origin).group(edition.copies)
        XCTAssertEqual(withSel, Proximity(selectedLibraries: ["eugenio_trias"], radiusKm: 5).group(edition.copies))
    }
}
