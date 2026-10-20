import Foundation
import SwiftSoup
import ZahoriCore

/// Parses the reader area of the OPAC ("Identifícame" → "Mi biblioteca").
/// Everything is keyed on element names, ids and CSS classes, never on accented labels.
public struct ReaderParser: Sendable {
    public init() {}

    public struct LoginForm: Equatable, Sendable {
        public var action: String
        /// Hidden inputs in document order (ACC=201, FBC, NAC on the current OPAC).
        public var hiddenFields: [(String, String)]
        public var cardField: String
        public var passwordField: String

        public static func == (a: LoginForm, b: LoginForm) -> Bool {
            a.action == b.action && a.cardField == b.cardField && a.passwordField == b.passwordField
                && a.hiddenFields.map { "\($0.0)=\($0.1)" } == b.hiddenFields.map { "\($0.0)=\($0.1)" }
        }
    }

    /// `<form name="abnopid">` with a text field (card number) and a password field.
    public func loginForm(_ html: String) -> LoginForm? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let forms = Soup.all(in: doc, tag: "form")
        guard let form = forms.first(where: { Soup.attr($0, "name") == "abnopid" })
                ?? forms.first(where: { f in Soup.all(in: f, tag: "input").contains { Soup.attr($0, "type") == "password" } }),
              let action = Soup.attr(form, "action"), !action.isEmpty else { return nil }

        var hidden: [(String, String)] = []
        var card: String?
        var password: String?
        for input in Soup.all(in: form, tag: "input") {
            guard let name = Soup.attr(input, "name"), !name.isEmpty else { continue }
            switch (Soup.attr(input, "type") ?? "text").lowercased() {
            case "hidden": hidden.append((name, Soup.attr(input, "value") ?? ""))
            case "password": password = password ?? name
            case "text", "number", "tel": card = card ?? name
            default: break
            }
        }
        guard let card, let password else { return nil }
        return LoginForm(action: action, hiddenFields: hidden, cardField: card, passwordField: password)
    }

    /// Logged-in pages have the "Desconectar" link (ACC=202) and no password field.
    public func isLoggedIn(_ html: String) -> Bool {
        guard let doc = try? SwiftSoup.parse(html) else { return false }
        return link(doc, acc: "202") != nil && !hasPasswordField(doc)
    }

    public func hasPasswordField(_ html: String) -> Bool {
        guard let doc = try? SwiftSoup.parse(html) else { return false }
        return hasPasswordField(doc)
    }

    /// "Mi biblioteca" (ACC=210).
    public func myLibraryLink(_ html: String) -> String? {
        (try? SwiftSoup.parse(html)).flatMap { link($0, acc: "210") }
    }

    /// "Desconectar" (ACC=202).
    public func logoutLink(_ html: String) -> String? {
        (try? SwiftSoup.parse(html)).flatMap { link($0, acc: "202") }
    }

    public enum LoansPage: Equatable, Sendable {
        case loans([Loan])
        /// Not the Mi biblioteca page we know (markup changed or session lost).
        case unrecognized
    }

    /// Port target: `li[id^=lector_box]` inside the "Préstamos / Renovar" accordion (`#lector_PR`).
    public func parseLoans(_ html: String, baseURL: URL) -> LoansPage {
        guard let doc = try? SwiftSoup.parse(html) else { return .unrecognized }
        let section = Soup.descendants(doc).first { Soup.attr($0, "id") == "lector_PR" }
            ?? Soup.descendants(doc).first { Soup.classContains($0, "js-lector_biblioPresta") }
        guard let section else { return .unrecognized }

        let items = Soup.all(in: section, tag: "li").filter { (Soup.attr($0, "id") ?? "").hasPrefix("lector_box") }
        return .loans(items.compactMap { loan(from: $0, baseURL: baseURL) })
    }

    private func loan(from li: Element, baseURL: URL) -> Loan? {
        // Hidden machine-readable block: <p class="varJSONpr"><span class="prbarc">…</span>…</p>
        guard let data = Soup.all(in: li, tag: "p").first(where: { Soup.classes($0).contains("varJSONpr") }) else { return nil }
        func field(_ cls: String) -> String? {
            let v = Soup.text(Soup.all(in: data, tag: "span").first { Soup.classes($0).contains(cls) })
            return v.isEmpty ? nil : v
        }
        guard let barcode = field("prbarc") ?? Soup.attr(li, "data-prbarc"),
              let rawTitle = field("tititu"),
              let due = field("prfdev") else { return nil }

        var title = rawTitle
        while title.last == "/" || title.last == " " { title.removeLast() }

        // Visible details: the first "DD/MM/YYYY HH:MM" text is the loan date, the other text is the shelfmark.
        var loanDate: String?
        var shelfmark: String?
        for span in Soup.all(in: li, tag: "span") where Soup.classes(span).contains("lector_boxDataInfoTxt") {
            let t = Soup.text(span)
            if loanDate == nil, PyText.matches(#"^\d{2}/\d{2}/\d{4}"#, t) { loanDate = t } else if shelfmark == nil, !t.isEmpty { shelfmark = t }
        }

        let titleLink = Soup.all(in: li, tag: "h4").first.flatMap { Soup.first(in: $0, tag: "a") }
        let recordURL = titleLink.flatMap { Soup.attr($0, "href") }
            .flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteString }

        return Loan(
            barcode: barcode,
            title: title,
            branch: field("description") ?? "",
            branchAddress: field("address"),
            dueDateTime: due,
            loanDateTime: loanDate,
            shelfmark: shelfmark,
            renewalsUsed: Int(field("prnren") ?? "") ?? 0,
            renewalsMax: Int(field("ppdrnm") ?? "") ?? 0,
            renewalWindowDays: Int(field("ppdrna") ?? "") ?? 0,
            reservations: Int(field("xsresv") ?? "") ?? 0,
            recordURL: recordURL
        )
    }

    private func link(_ doc: Document, acc: String) -> String? {
        Soup.all(in: doc, tag: "a").lazy.compactMap { Soup.attr($0, "href") }.first {
            PyText.matches("[?&]ACC=\(acc)(?:&|#|$)", $0)
        }
    }

    private func hasPasswordField(_ doc: Document) -> Bool {
        Soup.all(in: doc, tag: "input").contains { (Soup.attr($0, "type") ?? "").lowercased() == "password" }
    }
}
