"""Generates golden expectations for the Swift tests by running the Python reference implementation.

Run from the repository root:  python3 ios/Scripts/make_golden.py
Writes:
  ios/ZahoriKit/Sources/ZahoriCore/Resources/libraries.json   (verbatim copy of MADRID_LIBRARIES_DB)
  ios/ZahoriKit/Tests/ZahoriKitTests/Fixtures/golden.json     (expected outputs for every fixture)
"""

import asyncio
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

import httpx  # noqa: E402

from backend import goodreads_service, main  # noqa: E402
from backend.goodreads_service import (  # noqa: E402
    clean_book_title_for_search,
    extract_goodreads_user_id,
    extract_goodreads_user_name,
)
from backend.madrid_libraries_geo import (  # noqa: E402
    MADRID_LIBRARIES_DB,
    find_library_geo,
    get_all_libraries_list,
    haversine_distance,
    normalize_text,
)
from backend.models import BatchBookQuery, BookResult, SearchResponse  # noqa: E402
from backend.scraper import AbsysNetScraper  # noqa: E402
from tests.test_scraper import SAMPLE_DETAIL_HTML  # noqa: E402

FIX = ROOT / "ios/ZahoriKit/Tests/ZahoriKitTests/Fixtures"
RES = ROOT / "ios/ZahoriKit/Sources/ZahoriCore/Resources"
LIST_BASE = "https://gestiona.comunidad.madrid/biblio_publicas/cgi-bin/abnetopac/TOKEN?ACC=120&FORM=2"

scraper = AbsysNetScraper()


def read(name: str) -> str:
    return (FIX / name).read_text(encoding="latin-1")


def dump(model):
    return model.model_dump() if hasattr(model, "model_dump") else model


async def parse_rss(xml_name: str, user_input: str):
    """Runs fetch_goodreads_shelf against a mocked transport serving the fixture."""
    body = (FIX / xml_name).read_bytes()
    real_client = httpx.AsyncClient

    def fake_client(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(lambda req: httpx.Response(200, content=body))
        return real_client(*args, **kwargs)

    goodreads_service.httpx.AsyncClient = fake_client
    try:
        books, name = await goodreads_service.fetch_goodreads_shelf(user_input, "to-read")
    finally:
        goodreads_service.httpx.AsyncClient = real_client
    return {"user_name": name, "books": [b.model_dump() for b in books]}


async def batch_summary(book: BookResult, selected, radius, success=True):
    """Runs main._check_single_book_availability with scraper.search stubbed to return `book`."""
    async def fake_search(**kwargs):
        b = BookResult(**book.model_dump())
        if not success:
            return SearchResponse(success=False, error="boom")
        scraper._apply_geospatial_grouping([b], kwargs["selected_libraries"] or [], kwargs["radius_km"])
        return SearchResponse(success=True, total_editions=3, results=[b])

    original = main.scraper.search
    main.scraper.search = fake_search
    try:
        item = BatchBookQuery(book_id="b1", title="Cien años de soledad", author="García Márquez")
        res = await main._check_single_book_availability(item, selected, radius)
    finally:
        main.scraper.search = original
    d = res.model_dump()
    d.pop("full_result")
    return d


def main_():
    RES.mkdir(parents=True, exist_ok=True)
    (RES / "libraries.json").write_text(
        json.dumps(list(MADRID_LIBRARIES_DB.values()), ensure_ascii=False, indent=1), encoding="utf-8"
    )

    detail_html = read("opac_detail_cien_anos.html")
    detail_book = scraper._parse_detail_page(detail_html, "DOC_URL")

    branch_names = sorted({h.library for h in detail_book.holdings} | {
        "CARABANCHEL. BP La Chata", "José Luis Sampedro", "RETIRO. BP Eugenio Trías",
        "CHAMARTÍN. BP Dámaso Alonso", "MONCLOA-ARAVACA. BP Acuña", "Biblioteca Pública José Acuña",
        "Biblioteca Municipal de Alcorcón", "SALAMANCA. BP Manuel Alvar", "", "Sucursal desconocida XYZ",
        "eugenio_trias", "jose_acuna", "Retiro", "Chamartín",
    } | {lib["name"] for lib in MADRID_LIBRARIES_DB.values()})

    eugenio = MADRID_LIBRARIES_DB["eugenio_trias"]
    groupings = []
    for selected, radius in [
        (["eugenio_trias"], 5.0), (["eugenio_trias"], 1.0), (["eugenio_trias", "jose_acuna"], 3.0),
        (["damaso_alonso"], 20.0), ([], 5.0), (["RETIRO. BP Eugenio Trías"], 5.0), (["unknown_id"], 5.0),
    ]:
        b = BookResult(**detail_book.model_dump())
        scraper._apply_geospatial_grouping([b], selected, radius)
        groupings.append({
            "selected": selected, "radius_km": radius,
            "direct": [dump(h) for h in b.direct_matches],
            "nearby": [dump(h) for h in b.nearby_matches],
            "other": [dump(h) for h in b.other_holdings],
        })

    async def batches():
        out = []
        for selected, radius, success in [
            (["eugenio_trias"], 5.0, True), (["ortega_y_gasset"], 5.0, True), (["jose_luis_sampedro"], 5.0, True),
            (["canillejas"], 1.0, True), ([], 5.0, True), (["eugenio_trias"], 5.0, False),
        ]:
            out.append({"selected": selected, "radius_km": radius, "success": success,
                        "result": await batch_summary(detail_book, selected, radius, success)})
        # Book with all copies on loan
        loaned = BookResult(**detail_book.model_dump())
        loaned.holdings = [h for h in loaned.holdings if not h.is_available]
        for selected in (["jose_luis_sampedro"], ["eugenio_trias"]):
            out.append({"selected": selected, "radius_km": 5.0, "success": True, "only_loaned": True,
                        "result": await batch_summary(loaned, selected, 5.0)})
        return out

    titles = [
        "Dune (Dune Chronicles, #1)", "The Fellowship of the Ring (The Lord of the Rings, #1)",
        "Harry Potter and the Sorcerer's Stone (Harry Potter, #1)", "Watchmen [Graphic Novel]",
        "1984 (Signet Classics)", "Cien años de soledad (Edición 50 Aniversario)",
        "Sapiens: A Brief History of Humankind",
        "El infinito en un junco: La invención de los libros en el mundo antiguo",
        "For Love of Country: Common Sense 2.0", "It: A Novel", "Ab: cd", "  ", "",
        "¿Quién se ha llevado mi queso? (Spanish Edition)", "Los renglones torcidos de Dios (Booket)",
        "Rayuela (Cátedra)", "La sombra del viento (El Cementerio de los Libros Olvidados, #1)",
        "Ñandú & Co. — «edición» ½", "Tokyo Blues (Norwegian Wood)", "A/B: C", "Niebla (Clásicos)",
    ]
    user_inputs = [
        "177587843", " 177587843 ", "https://www.goodreads.com/user/show/177587843-john-doe",
        "https://www.goodreads.com/user/show/99887766", "https://www.goodreads.com/review/list/12345678?shelf=to-read",
        "https://www.goodreads.com/review/list_rss/12345678", "my id is 1234567 ok", "abc", "", "1234",
    ]
    name_cases = [
        ["https://www.goodreads.com/user/show/155193797-javier-bermejo", None],
        ["https://www.goodreads.com/user/show/177587843-john-doe_smith", None],
        ["177587843", "Javier Bermejo's bookshelf: to-read"],
        ["177587843", "Ana García’s bookshelf: currently-reading"],
        ["177587843", "12345's bookshelf: read"],
        ["https://www.goodreads.com/user/show/1-ana-lopez?ref=nav/x", "12345's bookshelf: read"],
        ["177587843", "Goodreads: to-read"],
        ["", None],
    ]

    lib_ids = list(MADRID_LIBRARIES_DB)
    haversine = []
    for ref in ("eugenio_trias", "manuel_alvar"):
        r = MADRID_LIBRARIES_DB[ref]
        for i in lib_ids:
            o = MADRID_LIBRARIES_DB[i]
            haversine.append([r["lat"], r["lon"], o["lat"], o["lon"], haversine_distance(r["lat"], r["lon"], o["lat"], o["lon"])])
    haversine.append([40.4168, -3.7038, 40.4158, -3.6791, haversine_distance(40.4168, -3.7038, 40.4158, -3.6791)])

    golden = {
        "libraries_list_ids": [l["id"] for l in get_all_libraries_list()],
        "normalize": {s: normalize_text(s) for s in branch_names + ["Ñandú-Ça, va!", "  A  b  "]},
        "find_library_geo": {s: (find_library_geo(s) or {}).get("id") for s in branch_names},
        "haversine": haversine,
        "clean_title": {t: clean_book_title_for_search(t) for t in titles},
        "user_id": {u: extract_goodreads_user_id(u) for u in user_inputs},
        "user_name": [[i, t, extract_goodreads_user_name(i, channel_title=t)] for i, t in name_cases],
        "rss_live": asyncio.run(parse_rss("goodreads_to_read.xml", "177587843")),
        "rss_synthetic": asyncio.run(parse_rss("goodreads_synthetic.xml", "https://www.goodreads.com/user/show/155193797-ana-garcia")),
        "list_pages": {n: [[m, u] for m, u in scraper._parse_list_page(read(n), LIST_BASE)]
                       for n in ("opac_list_cien_anos.html", "opac_author_rowling.html", "opac_single_result.html")},
        "list_base_url": LIST_BASE,
        "detail_live": dump(detail_book),
        "detail_sample": dump(scraper._parse_detail_page(SAMPLE_DETAIL_HTML, "http://example.com/doc1")),
        "sample_detail_html": SAMPLE_DETAIL_HTML,
        "grouping": groupings,
        "batch": asyncio.run(batches()),
        "eugenio_trias": eugenio,
    }
    (FIX / "golden.json").write_text(json.dumps(golden, ensure_ascii=False, indent=1), encoding="utf-8")
    print("wrote", FIX / "golden.json", "and", RES / "libraries.json")


if __name__ == "__main__":
    main_()
