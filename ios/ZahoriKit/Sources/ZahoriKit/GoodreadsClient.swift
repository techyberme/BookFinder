import Foundation
import ZahoriCore

/// Fetches a public Goodreads shelf. Port of `fetch_goodreads_shelf` (backend/goodreads_service.py).
public struct GoodreadsClient: Sendable {
    public enum FetchError: Error, Equatable, LocalizedError {
        case invalidUser
        case notFound(shelf: String, userID: String)
        case http(Int)
        case invalidXML(String)
        case network(String)

        public var errorDescription: String? {
            switch self {
            case .invalidUser:
                return String(localized: "No se pudo identificar un ID de usuario de Goodreads válido.", bundle: .module)
            case let .notFound(shelf, user):
                return String(localized: "Estantería '\(shelf)' o usuario '\(user)' no encontrados en Goodreads. Asegúrese de que el perfil sea público.", bundle: .module)
            case let .http(code):
                return String(localized: "Error al obtener estantería de Goodreads (Código HTTP \(code)).", bundle: .module)
            case let .invalidXML(reason):
                return String(localized: "Respuesta XML no válida de Goodreads: \(reason)", bundle: .module)
            case let .network(reason):
                return String(localized: "Error al obtener estantería de Goodreads: \(reason)", bundle: .module)
            }
        }
    }

    public var timeout: TimeInterval
    public var protocolClasses: [AnyClass]

    public init(timeout: TimeInterval = 15, protocolClasses: [AnyClass] = []) {
        self.timeout = timeout
        self.protocolClasses = protocolClasses
    }

    public static func feedURL(userID: String, shelf: String) -> URL {
        var c = URLComponents(string: "https://www.goodreads.com/review/list_rss/\(userID)")!
        c.queryItems = [URLQueryItem(name: "shelf", value: shelf)]
        return c.url!
    }

    public struct Result: Sendable {
        public var userID: String
        public var shelf: String
        public var userName: String?
        public var books: [Book]
    }

    public func fetchShelf(userInput: String, shelf: String = "to-read") async throws -> Result {
        let userID = GoodreadsText.userID(from: userInput)
        guard !userID.isEmpty else { throw FetchError.invalidUser }
        let shelfName = PyText.strip(shelf).isEmpty ? "to-read" : PyText.strip(shelf)

        let http = HTTPClient(options: .init(
            timeout: timeout,
            headers: ["User-Agent": HTTPClient.userAgent, "Accept": "application/rss+xml, application/xml, text/xml, */*"],
            protocolClasses: protocolClasses))
        let response: HTTPResponse
        do {
            response = try await http.get(Self.feedURL(userID: userID, shelf: shelfName))
        } catch let e as NetworkError {
            throw FetchError.network(e.spanishDescription)
        }
        if response.status == 404 { throw FetchError.notFound(shelf: shelfName, userID: userID) }
        guard response.status == 200 else { throw FetchError.http(response.status) }

        do {
            let parsed = try GoodreadsRSSParser.parse(response.data, userInput: userInput)
            return Result(userID: userID, shelf: shelfName, userName: parsed.userName, books: parsed.books)
        } catch let GoodreadsRSSParser.ParseError.invalidXML(reason) {
            throw FetchError.invalidXML(reason)
        }
    }
}
