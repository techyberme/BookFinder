import Foundation
import ZahoriCore

/// Parses a Goodreads shelf RSS feed. Port of the XML half of `fetch_goodreads_shelf`.
/// The feed is well-formed XML, so Foundation's XMLParser is enough (no HTML parser needed).
public enum GoodreadsRSSParser {
    public struct Shelf: Hashable, Sendable {
        public var books: [Book]
        public var userName: String?
    }

    public enum ParseError: Error, Equatable {
        case invalidXML(String)
    }

    /// - Parameter userInput: the raw ID/URL the user typed; used as the name fallback (URL slug).
    public static func parse(_ data: Data, userInput: String) throws -> Shelf {
        let root = try XMLTree.parse(data)
        guard let channel = root.child("channel") else { return Shelf(books: [], userName: nil) }

        let userName = GoodreadsText.userName(from: userInput, channelTitle: channel.child("title")?.text)
        var books: [Book] = []

        for item in channel.children(named: "item") {
            func text(_ tag: String, _ fallback: String = "") -> String {
                guard let t = item.child(tag)?.text else { return fallback }
                let s = PyText.strip(t)
                return s.isEmpty ? fallback : s
            }
            func first(_ tags: String...) -> String {
                for t in tags { let v = text(t); if !v.isEmpty { return v } }
                return ""
            }

            let rawTitle = text("title")
            if rawTitle.isEmpty { continue }

            let bookID = first("book_id", "guid")
            var cover: String? = first("book_large_image_url", "book_medium_image_url", "book_image_url")
            if let c = cover, c.contains("nophoto") { cover = nil }
            let isbn = first("isbn", "isbn13")
            let shelves = text("user_shelves")
            let link = text("link")
            let clean = GoodreadsText.cleanTitleForSearch(rawTitle)

            books.append(Book(
                bookID: bookID.isEmpty ? "gr_\(books.count + 1)" : bookID,
                title: rawTitle,
                cleanTitle: clean.isEmpty ? rawTitle : clean,
                author: text("author_name"),
                isbn: isbn.isEmpty ? nil : isbn,
                coverImageURL: cover,
                userRating: Int(text("user_rating", "0")) ?? 0,
                userShelves: shelves.isEmpty ? nil : shelves,
                dateAdded: first("user_date_added", "pubDate"),
                link: link.isEmpty ? nil : link
            ))
        }
        return Shelf(books: books, userName: userName)
    }
}

/// Minimal ElementTree: `text` is the character data before the first child element, like `Element.text`.
final class XMLTree {
    let name: String
    var text: String?
    var children: [XMLTree] = []

    init(name: String) { self.name = name }

    func child(_ name: String) -> XMLTree? { children.first { $0.name == name } }
    func children(named name: String) -> [XMLTree] { children.filter { $0.name == name } }

    static func parse(_ data: Data) throws -> XMLTree {
        let delegate = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            let reason = parser.parserError?.localizedDescription ?? "documento vacío"
            throw GoodreadsRSSParser.ParseError.invalidXML(reason)
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLTree?
        var stack: [XMLTree] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let el = XMLTree(name: name)
            if let parent = stack.last { parent.children.append(el) } else { root = el }
            stack.append(el)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { append(string) }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            append(String(decoding: block, as: UTF8.self))
        }

        private func append(_ s: String) {
            guard let el = stack.last, el.children.isEmpty else { return }
            el.text = (el.text ?? "") + s
        }
    }
}
