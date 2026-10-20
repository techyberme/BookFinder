import Foundation

/// Availability summary for one shelf book. Port of `BatchBookAvailabilityResult` and the summary
/// rules in `_check_single_book_availability` (backend/main.py).
public struct Availability: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case available
        /// In the catalog, no copy on the shelf right now.
        case onLoan
        /// The catalog answered and has no record (or the query was empty).
        case notInCatalog
        /// The catalog could not be reached or returned markup we do not understand.
        case catalogUnavailable
    }

    public var state: State
    public var isAvailable: Bool { state == .available }
    public var totalEditions: Int
    public var totalCopies: Int
    public var totalAvailableCopies: Int
    public var statusSummary: String
    public var bestMatchLibrary: String?
    public var bestMatchDistanceKm: Double?
    public var directMatchesCount: Int
    public var directMatchesAvailable: Int
    /// Python's `full_result`: the first edition, used by the book detail screen.
    public var firstEdition: Edition?
    public var isPartial: Bool

    public static func summarize(_ result: SearchResult, proximity: Proximity) -> Availability {
        switch result.outcome {
        case .invalidQuery, .noResults:
            return .empty(state: .notInCatalog, summary: String(localized: "No encontrado en catálogo", bundle: .module))
        case .catalogUnavailable:
            return .empty(state: .catalogUnavailable, summary: String(localized: "Catálogo no disponible", bundle: .module))
        case let .found(editions, totalEditions, isPartial):
            guard !editions.isEmpty else {
                return .empty(state: .notInCatalog, summary: String(localized: "No encontrado en catálogo", bundle: .module))
            }
            var all: [Copy] = [], direct: [Copy] = [], nearby: [Copy] = []
            for e in editions {
                let g = proximity.group(e.copies)
                all += e.copies
                direct += g.direct
                nearby += g.nearby
            }
            let totalAvail = all.filter(\.isAvailable).count
            let isAvailable = totalAvail > 0
            let directAvail = direct.filter(\.isAvailable)

            var bestLib: String?
            var bestDist: Double?
            let summary: String
            if let first = directAvail.first {
                bestLib = first.library
                bestDist = 0
                summary = String(localized: "Disponible en \(first.library)", bundle: .module)
            } else if let first = direct.first, !isAvailable {
                summary = String(localized: "Prestado en \(first.library)", bundle: .module)
            } else if let first = nearby.first(where: \.isAvailable) {
                bestLib = first.library
                bestDist = first.distanceKm
                let km = String(format: "%.1f", first.distanceKm ?? 0)
                summary = String(localized: "Disponible en \(first.library) (a \(km) km)", bundle: .module)
            } else if let first = all.first(where: \.isAvailable) {
                bestLib = first.library
                summary = String(localized: "Disponible en \(first.library)", bundle: .module)
            } else if !all.isEmpty {
                summary = String(localized: "Prestado (\(all.count) ejemplares en red)", bundle: .module)
            } else {
                summary = String(localized: "No disponible", bundle: .module)
            }

            return Availability(
                state: isAvailable ? .available : .onLoan,
                totalEditions: totalEditions,
                totalCopies: all.count,
                totalAvailableCopies: totalAvail,
                statusSummary: summary,
                bestMatchLibrary: bestLib,
                bestMatchDistanceKm: bestDist,
                directMatchesCount: direct.count,
                directMatchesAvailable: directAvail.count,
                firstEdition: editions.first,
                isPartial: isPartial
            )
        }
    }

    private static func empty(state: State, summary: String) -> Availability {
        Availability(state: state, totalEditions: 0, totalCopies: 0, totalAvailableCopies: 0,
                     statusSummary: summary, bestMatchLibrary: nil, bestMatchDistanceKm: nil,
                     directMatchesCount: 0, directMatchesAvailable: 0, firstEdition: nil, isPartial: false)
    }
}
