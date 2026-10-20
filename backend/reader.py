"""Reader area of the OPAC ("Identifícame" → "Mi biblioteca"): login and current loans.

Port of the iOS `ReaderParser` / `ReaderClient` (ios/ZahoriKit/Sources/ZahoriKit/Reader*.swift).
Flow: OPAC session → POST `abnopid` (ACC=201) → "Mi biblioteca" (ACC=210) → parse → "Desconectar" (ACC=202).
Everything is keyed on element names, ids and CSS classes, never on accented labels.
Credentials are only relayed to the OPAC: never stored or logged here.
"""

import logging
import re
import urllib.parse
from typing import List, Optional, Tuple

import httpx
from bs4 import BeautifulSoup
from pydantic import BaseModel

from .scraper import AbsysNetScraper

logger = logging.getLogger(__name__)


class Loan(BaseModel):
    """A book currently on loan. Mirrors `Loan` in ZahoriCore/Loans.swift."""
    barcode: str
    title: str
    branch: str
    branch_address: Optional[str] = None
    due_date_time: str  # "DD/MM/YYYY HH:MM", Madrid time
    loan_date_time: Optional[str] = None
    shelfmark: Optional[str] = None
    renewals_used: int = 0
    renewals_max: int = 0
    renewal_window_days: int = 0
    reservations: int = 0
    record_url: Optional[str] = None


class InvalidCredentials(Exception):
    """The OPAC answered the login with the login form again."""


class CatalogUnavailable(Exception):
    """Network failure, handshake failure or markup we do not recognise."""


# --- Parsing ---


def login_form(html: str) -> Optional[Tuple[str, List[Tuple[str, str]], str, str]]:
    """`<form name="abnopid">` → (action, hidden fields in order, card field, password field)."""
    soup = BeautifulSoup(html, "html.parser")
    forms = soup.find_all("form")
    form = next((f for f in forms if f.get("name") == "abnopid"), None) or next(
        (f for f in forms if f.find("input", attrs={"type": "password"})), None
    )
    if not form or not form.get("action"):
        return None

    hidden: List[Tuple[str, str]] = []
    card = password = None
    for inp in form.find_all("input"):
        name = inp.get("name")
        if not name:
            continue
        kind = (inp.get("type") or "text").lower()
        if kind == "hidden":
            hidden.append((name, inp.get("value") or ""))
        elif kind == "password":
            password = password or name
        elif kind in ("text", "number", "tel"):
            card = card or name
    if not card or not password:
        return None
    return form["action"], hidden, card, password


def _link(soup: BeautifulSoup, acc: str) -> Optional[str]:
    pattern = re.compile(rf"[?&]ACC={acc}(?:&|#|$)")
    for a in soup.find_all("a", href=True):
        if pattern.search(a["href"]):
            return a["href"]
    return None


def _has_password_field(soup: BeautifulSoup) -> bool:
    return any((i.get("type") or "").lower() == "password" for i in soup.find_all("input"))


def is_logged_in(html: str) -> bool:
    """Logged-in pages have the "Desconectar" link (ACC=202) and no password field."""
    soup = BeautifulSoup(html, "html.parser")
    return _link(soup, "202") is not None and not _has_password_field(soup)


def has_password_field(html: str) -> bool:
    return _has_password_field(BeautifulSoup(html, "html.parser"))


def my_library_link(html: str) -> Optional[str]:
    return _link(BeautifulSoup(html, "html.parser"), "210")


def logout_link(html: str) -> Optional[str]:
    return _link(BeautifulSoup(html, "html.parser"), "202")


def parse_loans(html: str, base_url: str) -> Optional[List[Loan]]:
    """Loans in `li[id^=lector_box]` inside `#lector_PR`; None when the page is not the one we know."""
    soup = BeautifulSoup(html, "html.parser")
    section = soup.find(id="lector_PR") or soup.find(class_=lambda c: c and "js-lector_biblioPresta" in c)
    if not section:
        return None
    items = [li for li in section.find_all("li") if (li.get("id") or "").startswith("lector_box")]
    return [loan for loan in (_loan(li, base_url) for li in items) if loan]


def _loan(li, base_url: str) -> Optional[Loan]:
    # Hidden machine-readable block: <p class="varJSONpr"><span class="prbarc">…</span>…</p>
    data = next((p for p in li.find_all("p") if "varJSONpr" in (p.get("class") or [])), None)
    if not data:
        return None

    def field(cls: str) -> Optional[str]:
        span = next((s for s in data.find_all("span") if cls in (s.get("class") or [])), None)
        value = span.get_text(" ", strip=True) if span else ""
        return value or None

    def number(cls: str) -> int:
        try:
            return int(field(cls) or "")
        except ValueError:
            return 0

    barcode = field("prbarc") or li.get("data-prbarc")
    raw_title = field("tititu")
    due = field("prfdev")
    if not barcode or not raw_title or not due:
        return None

    # Visible details: the first "DD/MM/YYYY HH:MM" text is the loan date, the other text is the shelfmark.
    loan_date = shelfmark = None
    for span in li.find_all("span"):
        if "lector_boxDataInfoTxt" not in (span.get("class") or []):
            continue
        t = span.get_text(" ", strip=True)
        if loan_date is None and re.match(r"^\d{2}/\d{2}/\d{4}", t):
            loan_date = t
        elif shelfmark is None and t:
            shelfmark = t

    h4 = li.find("h4")
    title_link = h4.find("a") if h4 else None
    record_url = urllib.parse.urljoin(base_url, title_link["href"]) if title_link and title_link.get("href") else None

    return Loan(
        barcode=barcode,
        title=raw_title.rstrip("/ "),
        branch=field("description") or "",
        branch_address=field("address"),
        due_date_time=due,
        loan_date_time=loan_date,
        shelfmark=shelfmark,
        renewals_used=number("prnren"),
        renewals_max=number("ppdrnm"),
        renewal_window_days=number("ppdrna"),
        reservations=number("xsresv"),
        record_url=record_url,
    )


# --- Network flow ---


async def fetch_loans(card: str, password: str, scraper: AbsysNetScraper, transport=None) -> List[Loan]:
    """Logs in, reads the loans and logs out (best effort, even on errors)."""
    card = card.strip()
    if not card or not password:
        raise InvalidCredentials()

    async with httpx.AsyncClient(
        headers=scraper.headers, follow_redirects=True, timeout=scraper.timeout, transport=transport
    ) as client:
        try:
            _, _, form_page = await scraper._open_session(client)
        except Exception as e:
            raise CatalogUnavailable(f"No se pudo conectar con el catálogo de bibliotecas: {e}") from None

        form = login_form(form_page.text)
        if not form:
            raise CatalogUnavailable("No se encontró el formulario de acceso del lector")
        action, hidden, card_field, password_field = form
        action_url = urllib.parse.urljoin(str(form_page.url), action)

        # 1. Log in
        try:
            after = await client.post(action_url, data=dict(hidden + [(card_field, card), (password_field, password)]))
            after.raise_for_status()
        except Exception as e:
            raise CatalogUnavailable(f"Error al identificarse en el catálogo: {type(e).__name__}") from None
        page = after.text
        if not is_logged_in(page):
            if has_password_field(page):
                raise InvalidCredentials()
            raise CatalogUnavailable("Respuesta de acceso no reconocida")

        # 2. Mi biblioteca
        after_url = str(after.url)
        library_url = urllib.parse.urljoin(after_url, my_library_link(page) or "?ACC=210")
        error: Optional[CatalogUnavailable] = None
        loans: List[Loan] = []
        try:
            library = await client.get(library_url)
            library.raise_for_status()
            parsed = parse_loans(library.text, str(library.url))
            if parsed is None:
                error = CatalogUnavailable("La página de préstamos no tiene el formato esperado")
            else:
                loans = parsed
        except Exception as e:
            error = CatalogUnavailable(f"Error al cargar tus préstamos: {type(e).__name__}")

        # 3. Close the reader session (best effort, errors ignored).
        logout = logout_link(page)
        if logout:
            try:
                await client.get(urllib.parse.urljoin(after_url, logout))
            except Exception:
                logger.info("Reader logout failed (ignored)")

        if error:
            raise error
        return loans


# --- Calendar export (web replacement for the iOS local notifications) ---


def _ics_text(value: str) -> str:
    return value.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def _fold(line: str) -> List[str]:
    """RFC 5545 line folding at 75 octets."""
    out, current = [], ""
    for ch in line:
        if len((current + ch).encode("utf-8")) > (75 if not out else 74):
            out.append(current)
            current = ch
        else:
            current += ch
    out.append(current)
    return [out[0]] + [" " + part for part in out[1:]]


def loans_calendar(loans: List[Loan], days_before: int, now_utc: str) -> str:
    """One all-day event per loan on its due date, with the same two alerts the iOS app schedules:
    `days_before` days before at 10:00 and on the due date at 10:00 (device time; the OPAC is Madrid time).
    Loans with an unreadable date are skipped. `now_utc` is the DTSTAMP, e.g. "20261020T120000Z"."""
    import datetime as dt

    days_before = min(max(days_before, 1), 7)
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Zahori//Prestamos//ES", "CALSCALE:GREGORIAN", "METHOD:PUBLISH"]
    for loan in loans:
        m = re.match(r"^(\d{2})/(\d{2})/(\d{4})", loan.due_date_time.strip())
        if not m:
            continue
        day = dt.date(int(m.group(3)), int(m.group(2)), int(m.group(1)))
        due_text = day.strftime("%d/%m/%Y")
        before = (
            f"Mañana vence el préstamo en {loan.branch}."
            if days_before == 1
            else f"El préstamo vence en {days_before} días ({due_text}) en {loan.branch}."
        )
        # All-day events start at 00:00, so "N days before at 10:00" is -(N days - 10 h).
        before_trigger = f"-P{days_before - 1}DT14H" if days_before > 1 else "-PT14H"
        details = f"Devolver antes del {due_text} en {loan.branch}."
        if loan.shelfmark:
            details += f" Signatura: {loan.shelfmark}."
        lines += [
            "BEGIN:VEVENT",
            f"UID:loan-{loan.barcode}-{day:%Y%m%d}@zahori",
            f"DTSTAMP:{now_utc}",
            f"DTSTART;VALUE=DATE:{day:%Y%m%d}",
            f"DTEND;VALUE=DATE:{day + dt.timedelta(days=1):%Y%m%d}",
            f"SUMMARY:{_ics_text('Devolver: ' + loan.title)}",
            f"LOCATION:{_ics_text(loan.branch_address or loan.branch)}",
            f"DESCRIPTION:{_ics_text(details)}",
            "BEGIN:VALARM", "ACTION:DISPLAY", f"DESCRIPTION:{_ics_text(before)}", f"TRIGGER:{before_trigger}", "END:VALARM",
            "BEGIN:VALARM", "ACTION:DISPLAY", f"DESCRIPTION:{_ics_text('Hoy vence el préstamo en ' + loan.branch + '.')}",
            "TRIGGER:PT10H", "END:VALARM",
            "END:VEVENT",
        ]
    lines.append("END:VCALENDAR")
    return "\r\n".join(folded for line in lines for folded in _fold(line)) + "\r\n"
