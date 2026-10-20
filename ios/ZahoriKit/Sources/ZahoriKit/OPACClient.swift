import Foundation
import ZahoriCore

/// Anything that can run a catalog search. `OPACClient` is the real one; tests inject fakes.
public protocol CatalogSearching: Sendable {
    func search(title: String, author: String, maxItems: Int) async -> SearchResult
}

/// AbsysNet OPAC client. Port of `AbsysNetScraper.search` (backend/scraper.py):
/// session handshake → advanced-search form → ACC=131/FORM=2 POST → list or detail parsing.
public struct OPACClient: CatalogSearching {
    public static let entryURL = URL(string: "https://gestiona.comunidad.madrid/biblio_publicas/cgi-bin/abnetopac?ACC=101")!

    public var parser: OPACParser
    /// Python: `AbsysNetScraper(timeout=20.0)` in backend/main.py.
    public var timeout: TimeInterval
    public var protocolClasses: [AnyClass]

    public init(parser: OPACParser = OPACParser(), timeout: TimeInterval = 20, protocolClasses: [AnyClass] = []) {
        self.parser = parser
        self.timeout = timeout
        self.protocolClasses = protocolClasses
    }

    static let headers = [
        "User-Agent": HTTPClient.userAgent,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
    ]

    /// Fresh client (and cookie jar) per search, exactly like `async with httpx.AsyncClient(...)`.
    func makeHTTP() -> HTTPClient {
        HTTPClient(options: .init(timeout: timeout, headers: Self.headers, protocolClasses: protocolClasses))
    }

    // MARK: - Payloads

    /// Form-2 payload. Field order matches the Python dicts (httpx keeps insertion order).
    public static func payload(title: String, author: String) -> [(String, String)] {
        let head: [(String, String)] = [("ACC", "131"), ("START", "1"), ("FORM", "2"), ("xsqf01", ""), ("subcat", "/")]
        let tail: [(String, String)] = [("xsnlis", "10"), ("xssort", "55088864")]
        if title.isEmpty && !author.isEmpty {
            return head + [("xsnf12", "4"), ("xsqf12", author), ("xsqf03", author)] + tail
        }
        return head + [("xsnf12", "0"), ("xsqf12", title), ("xsqf03", author)] + tail
    }

    /// Keyword fallback used when an author-only search finds nothing.
    public static func keywordPayload(_ author: String) -> [(String, String)] {
        [("ACC", "131"), ("START", "1"), ("FORM", "2"), ("xsqf01", author), ("subcat", "/"),
         ("xsnlis", "10"), ("xssort", "55088864")]
    }

    /// Title: collapse whitespace. Author: dots → spaces ("J.K. Rowling" → "J K Rowling"), collapse whitespace.
    public static func cleanQuery(title: String, author: String) -> (title: String, author: String) {
        let t = PyText.strip(PyText.sub(#"\s+"#, " ", title))
        let a = PyText.strip(PyText.sub(#"\s+"#, " ", PyText.sub(#"\.+"#, " ", author)))
        return (t, a)
    }

    // MARK: - Session

    struct Session {
        var http: HTTPClient
        var actionURL: URL
        /// The advanced-search page; it also carries the reader login form (`abnopid`).
        var formPage: HTTPResponse
    }

    enum HandshakeError: Error {
        case noRedirect
    }

    func openSession() async throws -> Session {
        let http = makeHTTP()
        let entry = try await http.get(Self.entryURL)
        guard entry.status == 200 else { throw NetworkError.http(status: entry.status) }
        guard let redirect = parser.sessionRedirect(entry.text),
              let sessionURL = URL(string: redirect, relativeTo: entry.url)?.absoluteURL else {
            throw HandshakeError.noRedirect
        }

        let home = try await http.get(sessionURL)
        guard home.status == 200 else { throw NetworkError.http(status: home.status) }

        let advURL = URL(string: "?ACC=120&FORM=2", relativeTo: sessionURL)!.absoluteURL
        let adv = try await http.get(advURL)
        guard adv.status == 200 else { throw NetworkError.http(status: adv.status) }

        let action = parser.formAction(adv.text).flatMap { URL(string: $0, relativeTo: advURL)?.absoluteURL } ?? advURL
        return Session(http: http, actionURL: action, formPage: adv)
    }

    // MARK: - Search

    public func search(title: String, author: String, maxItems: Int) async -> SearchResult {
        let rawTitle = PyText.strip(title)
        let rawAuthor = PyText.strip(author)
        guard !rawTitle.isEmpty || !rawAuthor.isEmpty else {
            return SearchResult(queryTitle: rawTitle, queryAuthor: rawAuthor, outcome: .invalidQuery)
        }
        let outcome = await runSearch(title: rawTitle, author: rawAuthor, maxItems: maxItems)
        return SearchResult(queryTitle: rawTitle, queryAuthor: rawAuthor, outcome: outcome)
    }

    private func runSearch(title: String, author: String, maxItems: Int) async -> SearchOutcome {
        let session: Session
        do {
            session = try await openSession()
        } catch is CancellationError {
            return .catalogUnavailable(reason: String(localized: "Búsqueda cancelada", bundle: .module))
        } catch {
            return .catalogUnavailable(reason: String(localized: "No se pudo conectar con el catálogo de bibliotecas: \(Self.describe(error))", bundle: .module))
        }

        let q = Self.cleanQuery(title: title, author: author)
        var page: HTTPResponse
        do {
            page = try await session.http.postForm(session.actionURL, fields: Self.payload(title: q.title, author: q.author))
            guard page.status == 200 else { throw NetworkError.http(status: page.status) }
        } catch {
            return .catalogUnavailable(reason: String(localized: "Error al enviar la consulta al catálogo: \(Self.describe(error))", bundle: .module))
        }

        var html = page.text
        guard var doc = try? parser.parse(html) else {
            return .catalogUnavailable(reason: String(localized: "Respuesta del catálogo no válida", bundle: .module))
        }

        // Author-only search with no hits → keyword search, errors ignored (as in Python).
        if !parser.hasResultList(doc), !q.author.isEmpty, q.title.isEmpty,
           let fallback = try? await session.http.postForm(session.actionURL, fields: Self.keywordPayload(q.author)),
           fallback.status == 200, let fallbackDoc = try? parser.parse(fallback.text) {
            page = fallback
            html = fallback.text
            doc = fallbackDoc
        }

        switch parser.classify(doc, html: html) {
        case .noResults:
            return .noResults
        case .singleRecord:
            let edition = parser.parseDetail(doc, url: page.url.absoluteString)
            guard edition.title != OPACParser.untitled else {
                return .catalogUnavailable(reason: String(localized: "Ficha del catálogo sin título reconocible", bundle: .module))
            }
            return .found(editions: [edition], totalEditions: 1, isPartial: false)
        case .unrecognized:
            return .catalogUnavailable(reason: String(localized: "El catálogo devolvió una página no reconocida", bundle: .module))
        case .resultList:
            let entries = parser.parseList(doc, baseURL: page.url)
            guard !entries.isEmpty else {
                return .catalogUnavailable(reason: String(localized: "El catálogo devolvió una página no reconocida", bundle: .module))
            }
            let selected = Array(entries.prefix(maxItems))
            let fetched = await fetchDetails(selected, http: session.http)
            let failures = fetched.filter { !$0.ok }.count
            if failures == fetched.count {
                return .catalogUnavailable(reason: String(localized: "No se pudieron cargar las fichas del catálogo", bundle: .module))
            }
            return .found(editions: fetched.map(\.edition), totalEditions: entries.count, isPartial: failures > 0)
        }
    }

    /// Fetches detail pages concurrently (Python `asyncio.gather`), keeping list order.
    /// A failed page becomes a placeholder edition with no copies, as in `fetch_item_detail`.
    private func fetchDetails(_ entries: [OPACParser.ListEntry], http: HTTPClient) async -> [(edition: Edition, ok: Bool)] {
        await withTaskGroup(of: (Int, Edition, Bool).self) { group in
            for (i, entry) in entries.enumerated() {
                group.addTask {
                    let url = entry.detailURL.absoluteString
                    if let res = try? await http.get(entry.detailURL), res.status == 200,
                       var edition = try? parser.parseDetail(res.text, url: url) {
                        if edition.title.isEmpty || edition.title == OPACParser.untitled { edition.title = entry.title }
                        if edition.author?.isEmpty ?? true { edition.author = entry.author }
                        return (i, edition, true)
                    }
                    return (i, Edition(title: entry.title, author: entry.author, publication: entry.publication, detailURL: url), false)
                }
            }
            var out = [(Edition, Bool)?](repeating: nil, count: entries.count)
            for await (i, e, ok) in group { out[i] = (e, ok) }
            return out.map { (edition: $0!.0, ok: $0!.1) }
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case let e as NetworkError: return e.spanishDescription
        case is HandshakeError: return String(localized: "no se pudo iniciar la sesión del OPAC", bundle: .module)
        default: return error.localizedDescription
        }
    }
}
