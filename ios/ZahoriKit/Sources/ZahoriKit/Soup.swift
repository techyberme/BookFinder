import Foundation
import SwiftSoup
import ZahoriCore

/// BeautifulSoup-equivalent helpers on top of SwiftSoup, so the parser reads like backend/scraper.py.
enum Soup {
    /// `tag.get_text(" ", strip=True)`: every descendant text node (not script/style/comments),
    /// each stripped, empties dropped, joined by a single space.
    static func text(_ node: Node?) -> String {
        guard let node else { return "" }
        var parts: [String] = []
        collectText(node, into: &parts)
        return parts.joined(separator: " ")
    }

    private static func collectText(_ node: Node, into parts: inout [String]) {
        if let t = node as? TextNode {
            let s = PyText.strip(t.getWholeText())
            if !s.isEmpty { parts.append(s) }
            return
        }
        for child in node.getChildNodes() { collectText(child, into: &parts) }
    }

    /// bs4 `tag.string`: the text of a tag whose only child is a string (recursing through single children).
    static func string(_ el: Element) -> String? {
        let children = el.getChildNodes()
        guard children.count == 1 else { return nil }
        if let t = children[0] as? TextNode { return t.getWholeText() }
        if let e = children[0] as? Element { return string(e) }
        return nil
    }

    /// Descendants (excluding `root`) in document order.
    static func descendants(_ root: Element) -> [Element] {
        Array(((try? root.getAllElements())?.array() ?? []).dropFirst())
    }

    static func classes(_ el: Element) -> [String] {
        ((try? el.className()) ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// `find(tags, class_=lambda c: c and needle in c)` — bs4 tests each class token and the whole attribute.
    static func classContains(_ el: Element, _ needle: String) -> Bool {
        let raw = (try? el.className()) ?? ""
        return raw.contains(needle) || classes(el).contains { $0.contains(needle) }
    }

    static func first(in root: Element, tags: Set<String>, classContaining needle: String) -> Element? {
        descendants(root).first { tags.contains($0.tagName()) && classContains($0, needle) }
    }

    static func all(in root: Element, tag: String, classContaining needle: String) -> [Element] {
        all(in: root, tag: tag).filter { classContains($0, needle) }
    }

    /// Descendants with this tag name, in document order (root excluded, like bs4 `find_all`).
    static func all(in root: Element, tag: String) -> [Element] {
        ((try? root.getElementsByTag(tag))?.array() ?? []).filter { $0 !== root }
    }

    static func first(in root: Element, tag: String) -> Element? {
        all(in: root, tag: tag).first
    }

    static func attr(_ el: Element, _ name: String) -> String? {
        el.hasAttr(name) ? (try? el.attr(name)) : nil
    }

    /// Every text node in the document (bs4 `soup.find(string=...)` candidates), including comments.
    static func allStrings(_ node: Node) -> [String] {
        var out: [String] = []
        func walk(_ n: Node) {
            if let t = n as? TextNode { out.append(t.getWholeText()) }
            else if let d = n as? DataNode { out.append(d.getWholeData()) }
            else if let c = n as? Comment { out.append(c.getData()) }
            for child in n.getChildNodes() { walk(child) }
        }
        walk(node)
        return out
    }
}
