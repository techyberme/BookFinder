"""Reader area (login, loans, calendar) and search outcomes, against the iOS fixtures and a mocked OPAC.

Mirrors ios/ZahoriKit/Tests/ZahoriKitTests/ReaderTests.swift; all reader data in the fixtures is fictional.
"""

import asyncio
from pathlib import Path

import httpx
import pytest

from backend import reader
from backend.scraper import AbsysNetScraper

FIXTURES = Path(__file__).resolve().parent.parent / "ios/ZahoriKit/Tests/ZahoriKitTests/Fixtures"
BASE = "https://gestiona.comunidad.madrid/biblio_publicas/cgi-bin/abnetopac/O9xxWyO8fWMoka92hKLzER9FBka/NT1"


def fixture(name: str) -> str:
    return (FIXTURES / name).read_bytes().decode("latin-1")


def html(text: str, status: int = 200) -> httpx.Response:
    return httpx.Response(status, content=text.encode("latin-1"), headers={"content-type": "text/html; charset=iso-8859-1"})


# --- Parsing ---


def test_login_form_on_public_page():
    action, hidden, card, password = reader.login_form(fixture("opac_advanced_form.html"))
    assert (card, password) == ("leid", "lepass")
    assert [k for k, _ in hidden] == ["FBC", "NAC", "ACC"]
    assert dict(hidden)["ACC"] == "201"
    assert action.startswith("/biblio_publicas/cgi-bin/abnetopac/")


def test_logged_in_detection():
    after = fixture("lector_post_login.html")
    assert reader.is_logged_in(after)
    assert reader.my_library_link(after).endswith("ACC=210")
    assert reader.logout_link(after).endswith("ACC=202")
    anonymous = fixture("opac_advanced_form.html")
    assert not reader.is_logged_in(anonymous)
    assert reader.has_password_field(anonymous)


def test_parse_single_loan():
    (loan,) = reader.parse_loans(fixture("lector_loans.html"), BASE)
    assert loan.barcode == "2000000001"
    assert loan.title == "Rayuela"
    assert loan.branch == "MONCLOA-ARAVACA. BP Acuña"
    assert loan.branch_address == "C/ Quintana, 9 28008 MADRID"
    assert loan.due_date_time == "12/11/2026 23:59"
    assert loan.loan_date_time == "13/10/2026 16:45"
    assert loan.shelfmark == "N COR ray"
    assert (loan.renewals_used, loan.renewals_max, loan.renewal_window_days, loan.reservations) == (0, 1, 5, 0)
    assert loan.record_url == (
        "https://gestiona.comunidad.madrid/biblio_publicas/cgi-bin/abnetopac/O9xxWyO8fWMoka92hKLzER9FBka/NT41?TITN=1000000"
    )


def test_parse_several_and_no_loans():
    loans = reader.parse_loans(fixture("lector_loans_multi.html"), BASE)
    assert [l.due_date_time[:10] for l in loans] == ["12/11/2026", "25/10/2026", "02/11/2026"]
    assert loans[1].renewals_used == 1
    assert loans[2].reservations == 3
    assert loans[2].branch == "CHAMARTÍN. BP Dámaso Alonso"
    assert reader.parse_loans(fixture("lector_loans_empty.html"), BASE) == []


def test_unknown_page_is_unrecognized():
    assert reader.parse_loans(fixture("lector_post_login.html"), BASE) is None
    assert reader.parse_loans("<html><body>Mantenimiento</body></html>", BASE) is None


# --- Login flow (mocked network) ---


def opac(login_page: str, library_page=None, requests=None):
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if requests is not None:
            requests.append(request)
        if request.method == "POST":
            return html(login_page)
        if "ACC=210" in url:
            return html(library_page if library_page is not None else fixture("lector_loans_multi.html"))
        if "ACC=202" in url:
            return html("<html><body>Adiós</body></html>")
        if "ACC=120" in url:
            return html(fixture("opac_advanced_form.html"))
        if url.endswith("abnetopac?ACC=101"):
            return html(fixture("opac_session_entry.html"))
        if "ACC=101" in url:
            return html("<html><body>Inicio</body></html>")
        return html("not found", 404)

    return httpx.MockTransport(handler)


def run(coro):
    return asyncio.run(coro)


SCRAPER = AbsysNetScraper(timeout=5)


def test_login_fetches_loans_and_logs_out():
    reqs = []
    loans = run(reader.fetch_loans(" 1234567890 ", "Secreto123", SCRAPER, opac(fixture("lector_post_login.html"), requests=reqs)))
    assert len(loans) == 3
    post = next(r for r in reqs if r.method == "POST")
    assert post.content == b"FBC=316&NAC=317&ACC=201&leid=1234567890&lepass=Secreto123"
    assert any(r.url.query == b"ACC=210" for r in reqs)
    assert reqs[-1].url.query == b"ACC=202", "the reader session is closed at the end"


def test_wrong_password_is_invalid_credentials():
    reqs = []
    with pytest.raises(reader.InvalidCredentials):
        run(reader.fetch_loans("1234567890", "x", SCRAPER, opac(fixture("opac_advanced_form.html"), requests=reqs)))
    assert not any(r.url.query == b"ACC=210" for r in reqs)


def test_empty_credentials_never_hit_the_network():
    reqs = []
    with pytest.raises(reader.InvalidCredentials):
        run(reader.fetch_loans("  ", "x", SCRAPER, opac("", requests=reqs)))
    assert reqs == []


def test_unknown_login_response_is_catalog_unavailable():
    with pytest.raises(reader.CatalogUnavailable):
        run(reader.fetch_loans("1", "x", SCRAPER, opac("<html><body>Servicio en mantenimiento</body></html>")))


def test_changed_loans_page_is_unavailable_and_still_logs_out():
    reqs = []
    with pytest.raises(reader.CatalogUnavailable):
        run(reader.fetch_loans("1", "x", SCRAPER, opac(fixture("lector_post_login.html"), "<html>Nuevo diseño</html>", reqs)))
    assert reqs[-1].url.query == b"ACC=202"


def test_api_status_codes(monkeypatch):
    from fastapi.testclient import TestClient
    from backend import main

    async def wrong(card, password, scraper):
        raise reader.InvalidCredentials()

    monkeypatch.setattr(reader, "fetch_loans", wrong)
    client = TestClient(main.app)
    assert client.post("/api/reader/loans", json={"card": "1", "password": "x"}).status_code == 401

    async def down(card, password, scraper):
        raise reader.CatalogUnavailable("caído")

    monkeypatch.setattr(reader, "fetch_loans", down)
    r = client.post("/api/reader/loans", json={"card": "1", "password": "x"})
    assert (r.status_code, r.json()["detail"]) == (502, "caído")


# --- Calendar ---


def test_calendar_alerts_and_escaping():
    loans = [reader.Loan(barcode="A", title="Rayuela, ed. 2", branch="BP Acuña", due_date_time="12/11/2026 23:59"),
             reader.Loan(barcode="B", title="Sin fecha", branch="X", due_date_time="sin fecha")]
    ics = reader.loans_calendar(loans, 2, "20261020T100000Z")
    assert ics.count("BEGIN:VEVENT") == 1
    assert "DTSTART;VALUE=DATE:20261112" in ics and "DTEND;VALUE=DATE:20261113" in ics
    assert "TRIGGER:-P1DT14H" in ics  # 2 days before at 10:00 = 10/11 10:00
    assert "TRIGGER:PT10H" in ics  # due day at 10:00
    assert "SUMMARY:Devolver: Rayuela\\, ed. 2" in ics
    assert "UID:loan-A-20261112@zahori" in ics
    assert all(len(line.encode()) <= 75 for line in ics.split("\r\n"))
    assert "TRIGGER:-PT14H" in reader.loans_calendar(loans, 1, "20261020T100000Z")


def test_calendar_endpoint():
    import json
    from fastapi.testclient import TestClient
    from backend import main

    payload = json.dumps({"loans": [{"barcode": "A", "title": "Rayuela", "branch": "BP Acuña",
                                     "due_date_time": "12/11/2026 23:59"}], "days_before": 3})
    r = TestClient(main.app).post("/api/reader/calendar.ics", data={"payload": payload})
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/calendar")
    assert "TRIGGER:-P2DT14H" in r.text
    assert TestClient(main.app).post("/api/reader/calendar.ics", data={"x": "1"}).status_code == 400


# --- Search outcomes (iOS SearchOutcome rules) ---


def search_with(post_page: str, detail=None):
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if request.method == "POST":
            return html(post_page)
        if "ACC=165" in url:
            return detail(request) if detail else html(fixture("opac_detail_cien_anos.html"))
        if "ACC=120" in url:
            return html(fixture("opac_advanced_form.html"))
        if url.endswith("abnetopac?ACC=101"):
            return html(fixture("opac_session_entry.html"))
        return html("<html><body>Inicio</body></html>")

    real = httpx.AsyncClient

    class Patched(real):
        def __init__(self, *a, **kw):
            kw["transport"] = httpx.MockTransport(handler)
            super().__init__(*a, **kw)

    httpx.AsyncClient = Patched
    try:
        return run(AbsysNetScraper(timeout=5).search(title="Cien años de soledad", author="García Márquez", max_items=2))
    finally:
        httpx.AsyncClient = real


def test_outcomes():
    assert search_with(fixture("opac_no_results.html")).outcome == "no_results"
    found = search_with(fixture("opac_list_cien_anos.html"))
    assert (found.outcome, found.is_partial, found.success) == ("found", False, True)
    assert found.results[0].holdings

    unknown = search_with("<html><body>Nuevo diseño</body></html>")
    assert (unknown.outcome, unknown.success, unknown.results) == ("catalog_unavailable", True, [])

    down = search_with(fixture("opac_list_cien_anos.html"), detail=lambda r: html("error", 503))
    assert down.outcome == "catalog_unavailable"

    calls = []

    def half(request):
        calls.append(request)
        return html("error", 503) if len(calls) == 1 else html(fixture("opac_detail_cien_anos.html"))

    partial = search_with(fixture("opac_list_cien_anos.html"), detail=half)
    assert (partial.outcome, partial.is_partial) == ("found", True)
