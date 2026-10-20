import Foundation
import SwiftSoup
import ZahoriCore

/// Parses AbsysNet OPAC pages. Port of the `_parse_*` methods of `AbsysNetScraper` (backend/scraper.py).
/// Every method is pure (HTML string in, values out) so it can be tested against saved fixtures.
public struct OPACParser: Sendable {
    public var directory: LibraryDirectory

    public init(directory: LibraryDirectory = .shared) {
        self.directory = directory
    }

    public enum ParseError: Error, Equatable {
        case malformedHTML
    }

    /// What kind of page a search POST returned. Python decides this inline in `search()`.
    public enum PageKind: Equatable, Sendable {
        case resultList
        case noResults
        case singleRecord
        /// None of the markers we know. Python treats this as "0 results"; we report the catalog as
        /// unavailable instead, so changed markup is not shown as "book not found".
        case unrecognized
    }

    // MARK: - Page classification

    public func hasResultList(_ doc: Document) -> Bool {
        !Soup.all(in: doc, tag: "div", classContaining: "c-docs_info").isEmpty
    }

    public func classify(_ html: String) throws -> PageKind {
        let doc = try parse(html)
        return classify(doc, html: html)
    }

    func classify(_ doc: Document, html: String) -> PageKind {
        let hasDocs = hasResultList(doc)
        // The no-results check runs before the list check in Python, but a list page never contains those texts.
        let noResultsPattern = #"NO recupera resultados|no se han encontrado|0 docs\."#
        let noResults = Soup.allStrings(doc).contains { PyText.matches(noResultsPattern, $0, ignoreCase: true) }
            || html.contains("NO recupera resultados")
        if noResults { return .noResults }
        if hasDocs { return .resultList }

        let hasBibFields = Soup.all(in: doc, tag: "dt").contains {
            guard let s = Soup.string($0) else { return false }
            return PyText.matches("T[íi]tulo", s, ignoreCase: true)
        }
        let hasCopiesTable = !Soup.all(in: doc, tag: "td", classContaining: "copias_tableDisp").isEmpty
            || Soup.descendants(doc).contains { Soup.classContains($0, "js-evn-copiasDetail-indexSign") }
        if hasBibFields || hasCopiesTable { return .singleRecord }
        return .unrecognized
    }

    // MARK: - Holdings

    /// Port of `_parse_holdings_from_html`.
    public func parseHoldings(_ html: String) throws -> [Copy] {
        try parseHoldings(parse(html))
    }

    func parseHoldings(_ doc: Document) -> [Copy] {
        var copies: [Copy] = []
        for item in Soup.all(in: doc, tag: "div", classContaining: "c-accordion_item") {
            let header = Soup.first(in: item, tags: ["button", "h4", "div", "span"], classContaining: "accordion")
            var branch = PyText.strip(PyText.sub(#"^Sucursal:\s*"#, "", Soup.text(header), ignoreCase: true))
            if branch.isEmpty { branch = "Biblioteca Central / Red de Bibliotecas" }

            let geo = directory.find(branch)
            guard let table = Soup.first(in: item, tag: "table") else { continue }

            for row in Soup.all(in: table, tag: "tr") {
                let cells = Soup.all(in: row, tag: "td")
                guard cells.count >= 4 else { continue }

                let cellLoc = cells[0]
                var location: String?
                if let span = Soup.descendants(cellLoc).first(where: { $0.tagName() == "span" && Soup.classes($0).contains("icm_locSign") }) {
                    let t = Soup.text(span)
                    location = t.isEmpty ? nil : PyText.strip(PyText.sub("Adquisición subvencionada.*", "", t))
                }

                var shelfmark: String?
                var barcode: String?
                if let link = Soup.descendants(cellLoc).first(where: { $0.tagName() == "a" && Soup.classContains($0, "js-evn-copiasDetail-indexSign") }) {
                    shelfmark = Soup.text(link)
                    barcode = Soup.attr(link, "data-bc")
                } else if let m = PyText.search(#"([A-Z0-9\.\-\s]{3,20})$"#, Soup.text(cellLoc), group: 1) {
                    shelfmark = PyText.strip(m)
                }

                let itemType = PyText.strip(PyText.sub(#"^Tipo de ejemplar\s*"#, "", Soup.text(cells[1]), ignoreCase: true))
                let support = PyText.strip(PyText.sub(#"^Soporte\s*"#, "", Soup.text(cells[2]), ignoreCase: true))
                let statusText = PyText.strip(PyText.sub(#"^Disponibilidad\s*"#, "", Soup.text(cells[3]), ignoreCase: true))
                let status = Self.loanStatus(statusText)

                var copy = Copy(
                    library: branch,
                    location: nonEmpty(location) ?? "General",
                    shelfmark: nonEmpty(shelfmark) ?? "N/A",
                    barcode: barcode,
                    itemType: nonEmpty(itemType) ?? "Prestable",
                    support: nonEmpty(support) ?? "Libro",
                    statusRaw: status.text,
                    isAvailable: status.isAvailable,
                    dueDate: status.dueDate
                )
                copy.lat = geo?.lat
                copy.lon = geo?.lon
                copy.district = geo?.district
                copy.municipality = geo?.municipality
                copies.append(copy)
            }
        }
        return copies
    }

    /// The Disponible / Prestado rule from `_parse_holdings_from_html`.
    public static func loanStatus(_ statusText: String) -> (text: String, isAvailable: Bool, dueDate: String?) {
        if PyText.matches(#"\bdisponible\b"#, statusText, ignoreCase: true),
           !PyText.matches("despu[eé]s de|hasta|no disponible", statusText, ignoreCase: true) {
            return ("Disponible", true, nil)
        }
        if let date = PyText.search(#"(\d{2}/\d{2}/\d{4})"#, statusText, group: 1) {
            return ("Prestado (hasta \(date))", false, date)
        }
        return (statusText.isEmpty ? "No disponible" : statusText, false, nil)
    }

    // MARK: - Detail page

    public static let untitled = "Título no especificado"

    /// Port of `_parse_detail_page`.
    public func parseDetail(_ html: String, url: String?) throws -> Edition {
        try parseDetail(parse(html), url: url)
    }

    func parseDetail(_ doc: Document, url: String?) -> Edition {
        var meta: [String: String] = [:]
        for dt in Soup.all(in: doc, tag: "dt") {
            var sib = try? dt.nextElementSibling()
            while let s = sib, s.tagName() != "dd" { sib = try? s.nextElementSibling() }
            guard let dd = sib else { continue }
            var label = Soup.text(dt)
            while label.hasSuffix(":") { label.removeLast() }
            label = PyText.strip(label)
            if meta[label] == nil { meta[label] = Soup.text(dd) }
        }
        // Python `d.get(a) or d.get(b) or ...`: first non-empty value, else whatever the last key holds.
        func m(_ keys: String...) -> String? {
            for k in keys { if let v = meta[k], !v.isEmpty { return v } }
            return meta[keys[keys.count - 1]]
        }

        var title = m("Título", "Titulo")
        if title?.isEmpty ?? true {
            let heading = Soup.first(in: doc, tags: ["h1", "h2", "h3"], classContaining: "docs_h")
            title = heading.map(Soup.text) ?? Self.untitled
        }
        let publication = m("Publicación", "Publicacion", "Lugar / ed. / año")
        var year = m("Año", "Ano")
        if year?.isEmpty ?? true, let publication, !publication.isEmpty {
            if let y = PyText.search(#"\b(19\d{2}|20\d{2})\b"#, publication, group: 1) { year = y }
        }
        return Edition(
            title: title ?? Self.untitled,
            author: m("Autor/Autora", "Autor", "Autora"),
            publication: publication,
            year: year,
            edition: m("Edición", "Edicion"),
            isbn: m("ISBN"),
            description: m("Sumario, etc.", "Descripción física"),
            detailURL: url,
            copies: parseHoldings(doc)
        )
    }

    // MARK: - Result list

    public struct ListEntry: Hashable, Sendable {
        public var title: String
        public var author: String
        public var publication: String
        public var detailURL: URL
    }

    /// Port of `_parse_list_page`.
    public func parseList(_ html: String, baseURL: URL) throws -> [ListEntry] {
        try parseList(parse(html), baseURL: baseURL)
    }

    func parseList(_ doc: Document, baseURL: URL) -> [ListEntry] {
        Soup.all(in: doc, tag: "div", classContaining: "c-docs_info").compactMap { info in
            guard let link = Soup.descendants(info).first(where: {
                $0.tagName() == "a" && (Soup.attr($0, "href")?.contains("ACC=165") ?? false)
            }), let href = Soup.attr(link, "href"),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { return nil }

            func span(_ cls: String) -> String {
                Soup.text(Soup.descendants(info).first { $0.tagName() == "span" && Soup.classContains($0, cls) })
            }
            let author = span("c-docs_author")
            // "c-docs_title" also matches "c-docs_titleRest"; bs4 returns the first in document order too.
            let titleMain = span("c-docs_title")
            let titleRest = span("c-docs_titleRest")
            var full = "\(titleMain) \(titleRest)"
            while full.last == "/" { full.removeLast() }
            full = PyText.strip(full)
            let pub = Soup.first(in: info, tag: "dl").map(Soup.text) ?? ""
            return ListEntry(title: full.isEmpty ? "Sin título" : full, author: author, publication: pub, detailURL: url)
        }
    }

    // MARK: - Session pages

    /// The meta-refresh target on the OPAC entry page (`content="0; URL=..."`).
    public func sessionRedirect(_ html: String) -> String? {
        let pattern = #"^\s*\d+;\s*URL=(.+)$"#
        if let doc = try? parse(html), let metas = try? doc.select("meta[content]") {
            for meta in metas {
                if let content = Soup.attr(meta, "content"),
                   let url = PyText.search(pattern, content, group: 1, ignoreCase: true) {
                    return url
                }
            }
        }
        // Same regex the Python code runs over the raw text, for markup SwiftSoup might not expose as <meta>.
        return PyText.search(#"content=["']\d+;\s*URL=([^"']+)["']"#, html, group: 1, ignoreCase: true)
    }

    /// The `action` of `<form name="abnform">` on the advanced-search page.
    public func formAction(_ html: String) -> String? {
        guard let doc = try? parse(html),
              let form = Soup.all(in: doc, tag: "form").first(where: { Soup.attr($0, "name") == "abnform" }),
              let action = Soup.attr(form, "action"), !action.isEmpty else { return nil }
        return action
    }

    func parse(_ html: String) throws -> Document {
        do { return try SwiftSoup.parse(html) } catch { throw ParseError.malformedHTML }
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
