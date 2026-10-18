import Foundation

/// A book on a Goodreads shelf. Mirrors `GoodreadsBook` in backend/goodreads_service.py.
public struct Book: Codable, Hashable, Sendable, Identifiable {
    public var bookID: String
    public var title: String
    /// Sanitized title used for catalog search.
    public var cleanTitle: String
    public var author: String
    public var isbn: String?
    /// Kept exactly as Python produces it: `nil` for "nophoto" covers, `""` when the feed has no image tags.
    public var coverImageURL: String?
    public var userRating: Int
    public var userShelves: String?
    public var dateAdded: String?
    public var link: String?

    public var id: String { bookID }

    public init(bookID: String, title: String, cleanTitle: String, author: String, isbn: String? = nil,
                coverImageURL: String? = nil, userRating: Int = 0, userShelves: String? = nil,
                dateAdded: String? = nil, link: String? = nil) {
        self.bookID = bookID
        self.title = title
        self.cleanTitle = cleanTitle
        self.author = author
        self.isbn = isbn
        self.coverImageURL = coverImageURL
        self.userRating = userRating
        self.userShelves = userShelves
        self.dateAdded = dateAdded
        self.link = link
    }
}

/// A physical copy in a branch. Mirrors `HoldingItem` in backend/models.py.
public struct Copy: Codable, Hashable, Sendable {
    public var library: String
    public var location: String
    public var shelfmark: String
    public var barcode: String?
    public var itemType: String
    public var support: String
    /// Cleaned status text: "Disponible", "Prestado (hasta DD/MM/YYYY)" or the raw OPAC text.
    public var statusRaw: String
    public var isAvailable: Bool
    /// DD/MM/YYYY, exactly as printed by the OPAC.
    public var dueDate: String?

    public var lat: Double?
    public var lon: Double?
    public var district: String?
    public var municipality: String?

    // Filled in by `Proximity.group`.
    public var distanceKm: Double?
    public var relativeToLibrary: String?
    public var isDirectMatch: Bool = false

    public init(library: String, location: String, shelfmark: String, barcode: String? = nil,
                itemType: String, support: String, statusRaw: String, isAvailable: Bool,
                dueDate: String? = nil, lat: Double? = nil, lon: Double? = nil,
                district: String? = nil, municipality: String? = nil) {
        self.library = library
        self.location = location
        self.shelfmark = shelfmark
        self.barcode = barcode
        self.itemType = itemType
        self.support = support
        self.statusRaw = statusRaw
        self.isAvailable = isAvailable
        self.dueDate = dueDate
        self.lat = lat
        self.lon = lon
        self.district = district
        self.municipality = municipality
    }
}

/// A bibliographic record (edition) with its copies. Mirrors `BookResult`.
public struct Edition: Codable, Hashable, Sendable {
    public var title: String
    public var author: String?
    public var publication: String?
    public var year: String?
    public var edition: String?
    public var isbn: String?
    public var description: String?
    public var detailURL: String?
    public var copies: [Copy]

    public var totalCopies: Int { copies.count }
    public var availableCopies: Int { copies.filter(\.isAvailable).count }

    public init(title: String, author: String? = nil, publication: String? = nil, year: String? = nil,
                edition: String? = nil, isbn: String? = nil, description: String? = nil,
                detailURL: String? = nil, copies: [Copy] = []) {
        self.title = title
        self.author = author
        self.publication = publication
        self.year = year
        self.edition = edition
        self.isbn = isbn
        self.description = description
        self.detailURL = detailURL
        self.copies = copies
    }
}

/// Outcome of one catalog search. Replaces `SearchResponse.success/error` with explicit cases so a
/// catalog outage is never confused with "this book is not in the catalog".
public enum SearchOutcome: Codable, Hashable, Sendable {
    /// The catalog answered. `isPartial` is true when some edition detail pages could not be fetched.
    case found(editions: [Edition], totalEditions: Int, isPartial: Bool)
    /// The catalog answered and reported no matching records.
    case noResults
    /// Neither a title nor an author was given (Python: "Debe especificar al menos un título o un autor").
    case invalidQuery
    /// Network failure, session handshake failure, or markup we do not recognize.
    case catalogUnavailable(reason: String)
}

public struct SearchResult: Codable, Hashable, Sendable {
    public var queryTitle: String
    public var queryAuthor: String
    public var outcome: SearchOutcome

    public init(queryTitle: String, queryAuthor: String, outcome: SearchOutcome) {
        self.queryTitle = queryTitle
        self.queryAuthor = queryAuthor
        self.outcome = outcome
    }

    public var editions: [Edition] {
        if case let .found(editions, _, _) = outcome { return editions }
        return []
    }

    public var totalEditions: Int {
        if case let .found(_, total, _) = outcome { return total }
        return 0
    }

    public var totalCopies: Int { editions.reduce(0) { $0 + $1.totalCopies } }
    public var totalAvailableCopies: Int { editions.reduce(0) { $0 + $1.availableCopies } }
}
