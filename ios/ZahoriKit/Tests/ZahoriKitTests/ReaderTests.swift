import XCTest
import ZahoriCore
@testable import ZahoriKit

/// Reader area ("Mi biblioteca"): parsing on anonymised fixtures, the login flow, reminders.
/// Fixtures come from ios/Scripts/make_reader_fixtures.py; all reader data in them is fictional.
final class ReaderTests: XCTestCase {
    let parser = ReaderParser()
    let base = URL(string: "https://gestiona.comunidad.madrid/biblio_publicas/cgi-bin/abnetopac/TOKEN/NT41")!

    // MARK: Parsing

    func testLoginFormOnPublicPage() throws {
        let form = try XCTUnwrap(parser.loginForm(Fixture.latin1("opac_advanced_form.html")))
        XCTAssertEqual(form.cardField, "leid")
        XCTAssertEqual(form.passwordField, "lepass")
        XCTAssertEqual(form.hiddenFields.map(\.0), ["FBC", "NAC", "ACC"])
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: form.hiddenFields)["ACC"], "201")
        XCTAssert(form.action.hasPrefix("/biblio_publicas/cgi-bin/abnetopac/"))
    }

    func testLoggedInDetection() {
        let after = Fixture.latin1("lector_post_login.html")
        XCTAssertTrue(parser.isLoggedIn(after))
        XCTAssertNotNil(parser.myLibraryLink(after))
        XCTAssert(parser.myLibraryLink(after)!.hasSuffix("ACC=210"))
        XCTAssert(parser.logoutLink(after)!.hasSuffix("ACC=202"))

        let anonymous = Fixture.latin1("opac_advanced_form.html")
        XCTAssertFalse(parser.isLoggedIn(anonymous))
        XCTAssertTrue(parser.hasPasswordField(anonymous))
    }

    func testParseSingleLoan() throws {
        guard case let .loans(loans) = parser.parseLoans(Fixture.latin1("lector_loans.html"), baseURL: base) else {
            return XCTFail("unrecognized")
        }
        XCTAssertEqual(loans.count, 1)
        let l = loans[0]
        XCTAssertEqual(l.barcode, "2000000001")
        XCTAssertEqual(l.title, "Rayuela")
        XCTAssertEqual(l.branch, "MONCLOA-ARAVACA. BP Acuña")
        XCTAssertEqual(l.branchAddress, "C/ Quintana, 9 28008 MADRID")
        XCTAssertEqual(l.dueDateTime, "12/11/2026 23:59")
        XCTAssertEqual(l.dueDateText, "12/11/2026")
        XCTAssertEqual(l.loanDateTime, "13/10/2026 16:45")
        XCTAssertEqual(l.shelfmark, "N COR ray")
        XCTAssertEqual(l.renewalsUsed, 0)
        XCTAssertEqual(l.renewalsMax, 1)
        XCTAssertEqual(l.renewalWindowDays, 5)
        XCTAssertEqual(l.reservations, 0)
        XCTAssertEqual(l.recordURL, "https://gestiona.comunidad.madrid/biblio_publicas/cgi-bin/abnetopac/O9xxWyO8fWMoka92hKLzER9FBka/NT41?TITN=1000000")
        // The library is known to the directory, so it can be shown on the map/proximity later.
        XCTAssertEqual(LibraryDirectory.shared.find(l.branch)?.id, "jose_acuna")
    }

    func testParseSeveralLoans() {
        guard case let .loans(loans) = parser.parseLoans(Fixture.latin1("lector_loans_multi.html"), baseURL: base) else {
            return XCTFail("unrecognized")
        }
        XCTAssertEqual(loans.map(\.title), ["Rayuela", "Ficciones",
                                            "El infinito en un junco : la invención de los libros en el mundo antiguo"])
        XCTAssertEqual(loans.map(\.dueDateText), ["12/11/2026", "25/10/2026", "02/11/2026"])
        XCTAssertEqual(loans[1].renewalsUsed, 1)
        XCTAssertFalse(loans[1].hasRenewalsLeft)
        XCTAssertEqual(loans[2].reservations, 3)
        XCTAssertEqual(loans[2].branch, "CHAMARTÍN. BP Dámaso Alonso")
    }

    func testParseNoLoans() {
        XCTAssertEqual(parser.parseLoans(Fixture.latin1("lector_loans_empty.html"), baseURL: base), .loans([]))
    }

    func testUnknownPageIsUnrecognized() {
        XCTAssertEqual(parser.parseLoans(Fixture.latin1("lector_post_login.html"), baseURL: base), .unrecognized)
        XCTAssertEqual(parser.parseLoans("<html><body>Mantenimiento</body></html>", baseURL: base), .unrecognized)
    }

    // MARK: Dates and reminders (Madrid time)

    private func madrid(_ s: String) -> Date { LoanCalendar.parse(s)! }

    func testDueDateAndDaysLeft() {
        let loan = Loan(barcode: "1", title: "Rayuela", branch: "BP Acuña", dueDateTime: "12/11/2026 23:59",
                        renewalsUsed: 0, renewalsMax: 1, renewalWindowDays: 5)
        XCTAssertEqual(loan.daysUntilDue(from: madrid("19/10/2026 09:00")), 24)
        XCTAssertEqual(loan.daysUntilDue(from: madrid("12/11/2026 08:00")), 0)
        XCTAssertEqual(loan.daysUntilDue(from: madrid("14/11/2026 08:00")), -2)
        XCTAssertEqual(loan.renewableFrom, madrid("07/11/2026 00:00"))
        XCTAssertEqual(LoanCalendar.dayString(loan.renewableFrom!), "07/11/2026")
        var used = loan
        used.renewalsUsed = 1
        XCTAssertNil(used.renewableFrom)
    }

    func testDateWithoutTimeMeansEndOfDay() {
        XCTAssertEqual(LoanCalendar.calendar.dateComponents([.hour, .minute], from: madrid("12/11/2026")).hour, 23)
        XCTAssertNil(LoanCalendar.parse("sin fecha"))
    }

    func testReminderPlan() {
        let loans = [
            Loan(barcode: "A", title: "Rayuela", branch: "BP Acuña", dueDateTime: "12/11/2026 23:59"),
            Loan(barcode: "B", title: "Ficciones", branch: "BP Eugenio Trías", dueDateTime: "20/10/2026 23:59"),
            Loan(barcode: "C", title: "Vencido", branch: "BP Retiro", dueDateTime: "10/10/2026 23:59"),
        ]
        let now = madrid("19/10/2026 12:00")
        let plan = LoanReminders.plan(for: loans, daysBefore: 2, now: now)

        // B: "2 days before" (18/10) is past → only the due-day one. C overdue → none. A → both.
        XCTAssertEqual(plan.map(\.id), [
            "loan-B-20/10/2026-due",
            "loan-A-12/11/2026-before",
            "loan-A-12/11/2026-due",
        ])
        XCTAssertEqual(plan[0].fireDate, madrid("20/10/2026 10:00"))
        XCTAssertEqual(plan[1].fireDate, madrid("10/11/2026 10:00"))
        XCTAssertEqual(plan[1].title, "Rayuela")
        XCTAssert(plan[1].body.contains("2 días"))
        XCTAssert(plan[1].body.contains("12/11/2026"))
        XCTAssert(plan.allSatisfy { $0.id.hasPrefix(LoanReminders.idPrefix) && $0.fireDate > now })
    }

    func testOneDayBeforeWording() {
        let plan = LoanReminders.plan(for: [Loan(barcode: "A", title: "X", branch: "BP Acuña", dueDateTime: "12/11/2026 23:59")],
                                      daysBefore: 1, now: madrid("19/10/2026 12:00"))
        XCTAssert(plan[0].body.hasPrefix("Mañana vence"))
    }

    // MARK: Settings compatibility

    func testOldSettingsFileStillLoads() throws {
        let old = #"{"selectedLibraryIDs":["eugenio_trias"],"radiusKm":7,"goodreadsUserID":"1","shelf":"read"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.selectedLibraryIDs, ["eugenio_trias"])
        XCTAssertEqual(s.radiusKm, 7)
        XCTAssertEqual(s.shelf, "read")
        XCTAssertTrue(s.loanRemindersEnabled)
        XCTAssertEqual(s.reminderDaysBefore, 2)
    }

    // MARK: Login flow (mocked network)

    private let client = ReaderClient(opac: OPACClient(timeout: 5, protocolClasses: [MockURLProtocol.self]))
    private let credentials = ReaderCredentials(card: " 1234567890 ", password: "Secreto123")

    private func install(login: @escaping (String) -> MockURLProtocol.Reply,
                         library: MockURLProtocol.Reply = .fixture("lector_loans_multi.html")) {
        MockURLProtocol.install { request, body in
            let url = request.url!.absoluteString
            if request.httpMethod == "POST" { return login(body ?? "") }
            if url.contains("ACC=210") { return library }
            if url.contains("ACC=202") { return .html("<html><body>Adiós</body></html>") }
            if url.contains("ACC=120") { return .fixture("opac_advanced_form.html") }
            if url.hasSuffix("abnetopac?ACC=101") { return .fixture("opac_session_entry.html") }
            if url.contains("ACC=101") { return .html("<html><body>Inicio</body></html>") }
            return .html("not found", status: 404)
        }
    }

    func testLoginFetchesLoansAndLogsOut() async throws {
        install(login: { _ in .fixture("lector_post_login.html") })
        let loans = try await client.fetchLoans(credentials).get()
        XCTAssertEqual(loans.count, 3)

        let reqs = MockURLProtocol.requests
        let post = try XCTUnwrap(reqs.first { $0.method == "POST" })
        XCTAssertEqual(post.body, "FBC=316&NAC=317&ACC=201&leid=1234567890&lepass=Secreto123")
        XCTAssert(reqs.contains { $0.url.query == "ACC=210" })
        XCTAssertEqual(reqs.last?.url.query, "ACC=202", "the reader session is closed at the end")
    }

    func testWrongPasswordIsInvalidCredentials() async {
        // A failed login shows the login form again.
        install(login: { _ in .fixture("opac_advanced_form.html") })
        let result = await client.fetchLoans(credentials)
        XCTAssertEqual(result, .failure(.invalidCredentials))
        XCTAssertFalse(MockURLProtocol.requests.contains { $0.url.query == "ACC=210" })
    }

    func testEmptyCredentialsNeverHitTheNetwork() async {
        MockURLProtocol.install { _, _ in .html("") }
        let result = await client.fetchLoans(ReaderCredentials(card: "  ", password: "x"))
        XCTAssertEqual(result, .failure(.invalidCredentials))
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testOfflineIsCatalogUnavailable() async {
        MockURLProtocol.install { _, _ in .failure(.notConnectedToInternet) }
        guard case .failure(.catalogUnavailable) = await client.fetchLoans(credentials) else { return XCTFail() }
    }

    func testUnknownLoginResponseIsCatalogUnavailable() async {
        install(login: { _ in .html("<html><body>Servicio en mantenimiento</body></html>") })
        guard case .failure(.catalogUnavailable) = await client.fetchLoans(credentials) else { return XCTFail() }
    }

    func testChangedLoansPageIsCatalogUnavailableAndStillLogsOut() async {
        install(login: { _ in .fixture("lector_post_login.html") }, library: .html("<html><body>Nuevo diseño</body></html>"))
        guard case .failure(.catalogUnavailable) = await client.fetchLoans(credentials) else { return XCTFail() }
        XCTAssertEqual(MockURLProtocol.requests.last?.url.query, "ACC=202")
    }

    func testLoansCacheRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("loans-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONFileStore<CachedLoans>(url: url)
        let cached = CachedLoans(loans: [Loan(barcode: "A", title: "Rayuela", branch: "BP Acuña", dueDateTime: "12/11/2026 23:59")],
                                 fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(cached)
        XCTAssertEqual(store.load(), cached)
    }
}
