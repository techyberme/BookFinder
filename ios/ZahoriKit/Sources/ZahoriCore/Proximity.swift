import Foundation

public struct Coordinate: Codable, Hashable, Sendable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    /// Puerta del Sol. Used as the proximity origin when location permission is denied
    /// (same point the Python test suite uses as "Madrid center").
    public static let madridCenter = Coordinate(lat: 40.4168, lon: -3.7038)
}

public enum Geo {
    /// Port of `haversine_distance`: great-circle km, rounded to 2 decimals like Python's `round(x, 2)`.
    public static func haversineKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0
        let phi1 = lat1 * .pi / 180, phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180
        let a = pow(sin(dPhi / 2), 2) + cos(phi1) * cos(phi2) * pow(sin(dLambda / 2), 2)
        let c = 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
        return roundPy(r * c, places: 2)
    }

    public static func haversineKm(_ a: Coordinate, _ b: Coordinate) -> Double {
        haversineKm(a.lat, a.lon, b.lat, b.lon)
    }

    /// Python's `round(x, n)` is correctly rounded on the exact binary value, which is what `%.nf` does.
    static func roundPy(_ x: Double, places: Int) -> Double {
        Double(String(format: "%.\(places)f", x)) ?? x
    }
}

/// The three result sections shown for every edition.
public struct GroupedCopies: Hashable, Sendable {
    /// "Bibliotecas Seleccionadas"
    public var direct: [Copy]
    /// "Alternativas Cercanas": every copy within the radius (available or not, as in the Python code),
    /// sorted by distance, then available first.
    public var nearby: [Copy]
    /// "Otras Bibliotecas"
    public var other: [Copy]

    public init(direct: [Copy] = [], nearby: [Copy] = [], other: [Copy] = []) {
        self.direct = direct
        self.nearby = nearby
        self.other = other
    }
}

/// Port of `AbsysNetScraper._apply_geospatial_grouping`, with one extension: when no library is
/// selected and a `fallbackOrigin` is given (device location, or Madrid center), distances are measured
/// from that point instead of putting every copy in "other".
public struct Proximity: Sendable {
    public var directory: LibraryDirectory
    public var selectedLibraries: [String]
    public var radiusKm: Double
    public var fallbackOrigin: ReferencePoint?

    public struct ReferencePoint: Hashable, Sendable {
        public var name: String
        public var coordinate: Coordinate
        public init(name: String, coordinate: Coordinate) {
            self.name = name
            self.coordinate = coordinate
        }
    }

    public init(directory: LibraryDirectory = .shared, selectedLibraries: [String], radiusKm: Double,
                fallbackOrigin: ReferencePoint? = nil) {
        self.directory = directory
        self.selectedLibraries = selectedLibraries
        self.radiusKm = radiusKm
        self.fallbackOrigin = fallbackOrigin
    }

    /// Coordinates of the selected libraries (unknown ids/names are skipped, as in Python).
    public var referencePoints: [ReferencePoint] {
        selectedLibraries.compactMap { sel in
            guard let lib = directory.find(sel) ?? directory.library(id: sel) else { return nil }
            return ReferencePoint(name: lib.name, coordinate: lib.coordinate)
        }
    }

    public func group(_ copies: [Copy]) -> GroupedCopies {
        if selectedLibraries.isEmpty {
            guard let origin = fallbackOrigin else { return GroupedCopies(other: copies) }
            return groupByDistance(copies, refs: [origin], normSelected: [])
        }
        return groupByDistance(copies, refs: referencePoints,
                               normSelected: selectedLibraries.map(LibraryDirectory.normalize))
    }

    private func groupByDistance(_ copies: [Copy], refs: [ReferencePoint], normSelected: [String]) -> GroupedCopies {
        var result = GroupedCopies()
        for var copy in copies {
            let hNorm = LibraryDirectory.normalize(copy.library)
            var isDirect = normSelected.contains { $0.contains(hNorm) || hNorm.contains($0) }
            if !isDirect, !normSelected.isEmpty, let geo = directory.find(copy.library) {
                isDirect = selectedLibraries.contains(geo.id) || normSelected.contains(LibraryDirectory.normalize(geo.name))
            }
            if isDirect {
                copy.isDirectMatch = true
                copy.distanceKm = 0
                result.direct.append(copy)
                continue
            }

            guard !refs.isEmpty, let lat = copy.lat, let lon = copy.lon else {
                result.other.append(copy)
                continue
            }
            var minDist = Double.infinity
            var closest: String?
            for ref in refs {
                let d = Geo.haversineKm(lat, lon, ref.coordinate.lat, ref.coordinate.lon)
                if d < minDist {
                    minDist = d
                    closest = ref.name
                }
            }
            copy.relativeToLibrary = closest
            if minDist <= radiusKm {
                copy.distanceKm = minDist
                result.nearby.append(copy)
            } else {
                copy.distanceKm = minDist.isFinite ? minDist : nil
                result.other.append(copy)
            }
        }
        // Python: sort(key=(distance or 9999, not is_available)) — stable sort.
        result.nearby = result.nearby.enumerated().sorted { a, b in
            let da = a.element.distanceKm ?? 9999, db = b.element.distanceKm ?? 9999
            if da != db { return da < db }
            let ua = a.element.isAvailable ? 0 : 1, ub = b.element.isAvailable ? 0 : 1
            if ua != ub { return ua < ub }
            return a.offset < b.offset
        }.map(\.element)
        return result
    }
}
