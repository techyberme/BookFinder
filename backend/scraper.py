"""Scraper module for the Madrid Public Libraries Network (AbsysNet OPAC) with Geospatial Proximity."""

import asyncio
import logging
import re
import urllib.parse
from typing import List, Optional, Tuple
from bs4 import BeautifulSoup
import httpx

from .models import BookResult, HoldingItem, SearchResponse
from .madrid_libraries_geo import (
    MADRID_LIBRARIES_DB,
    find_library_geo,
    haversine_distance,
    normalize_text,
)

logger = logging.getLogger(__name__)

OPAC_BASE_URL = "https://gestiona.comunidad.madrid/biblio_publicas/cgi-bin/abnetopac?ACC=101"
DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/125.0.0.0 Safari/537.36"
)


class AbsysNetScraper:
    """Handles stateful session lifecycle, querying, parsing, and geo-filtering for AbsysNet OPAC."""

    def __init__(self, timeout: float = 15.0):
        self.timeout = timeout
        self.headers = {
            "User-Agent": DEFAULT_USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
        }

    async def _init_session(self, client: httpx.AsyncClient) -> Tuple[str, str]:
        """Initializes a new OPAC session and retrieves the session search URL and action URL."""
        session_url, action_url, _ = await self._open_session(client)
        return session_url, action_url

    async def _open_session(self, client: httpx.AsyncClient) -> Tuple[str, str, httpx.Response]:
        """Like `_init_session`, also returning the advanced-search page (it carries the reader login form)."""
        resp = await client.get(OPAC_BASE_URL, headers=self.headers, timeout=self.timeout)
        resp.raise_for_status()

        # Find meta-refresh URL containing session token
        match = re.search(r'content=["\']\d+;\s*URL=([^"\']+)["\']', resp.text, re.IGNORECASE)
        if not match:
            raise ValueError("Could not extract initial session redirect from AbsysNet OPAC response")

        redirect_path = match.group(1)
        session_url = urllib.parse.urljoin(str(resp.url), redirect_path)

        # Access session home
        resp_session = await client.get(session_url, headers=self.headers, timeout=self.timeout)
        resp_session.raise_for_status()

        # Access Advanced Search form (ACC=120&FORM=2) to get the proper action endpoint
        adv_url = urllib.parse.urljoin(session_url, "?ACC=120&FORM=2")
        resp_adv = await client.get(adv_url, headers=self.headers, timeout=self.timeout)
        resp_adv.raise_for_status()

        soup = BeautifulSoup(resp_adv.text, "html.parser")
        form = soup.find("form", {"name": "abnform"})
        if not form or not form.get("action"):
            action_url = adv_url
        else:
            action_url = urllib.parse.urljoin(adv_url, form["action"])

        return session_url, action_url, resp_adv

    def _parse_holdings_from_html(self, html: str) -> List[HoldingItem]:
        """Parses the holdings/copies accordion tables from an item detail page and enriches with geodata."""
        soup = BeautifulSoup(html, "html.parser")
        holdings: List[HoldingItem] = []

        accordion_items = soup.find_all("div", class_=lambda c: c and "c-accordion_item" in c)

        for item in accordion_items:
            # Extract branch/library name
            header_el = item.find(["button", "h4", "div", "span"], class_=lambda c: c and "accordion" in c)
            raw_header = header_el.get_text(" ", strip=True) if header_el else ""
            branch_name = re.sub(r"^Sucursal:\s*", "", raw_header, flags=re.IGNORECASE).strip()
            if not branch_name:
                branch_name = "Biblioteca Central / Red de Bibliotecas"

            # Geo lookup
            geo_info = find_library_geo(branch_name)
            lat = geo_info["lat"] if geo_info else None
            lon = geo_info["lon"] if geo_info else None
            district = geo_info["district"] if geo_info else None
            municipality = geo_info["municipality"] if geo_info else None

            table = item.find("table")
            if not table:
                continue

            for row in table.find_all("tr"):
                cells = row.find_all("td")
                if not cells or len(cells) < 4:
                    continue

                # Cell 0: Location / Shelfmark / Barcode
                cell_loc = cells[0]
                loc_span = cell_loc.find("span", class_="icm_locSign")
                location = loc_span.get_text(" ", strip=True) if loc_span else None
                if location:
                    location = re.sub(r"Adquisición subvencionada.*", "", location).strip()

                sign_link = cell_loc.find("a", class_=lambda c: c and "js-evn-copiasDetail-indexSign" in c)
                shelfmark = None
                barcode = None
                if sign_link:
                    shelfmark = sign_link.get_text(" ", strip=True)
                    barcode = sign_link.get("data-bc")
                else:
                    shelfmark_match = re.search(r"([A-Z0-9\.\-\s]{3,20})$", cell_loc.get_text(" ", strip=True))
                    if shelfmark_match:
                        shelfmark = shelfmark_match.group(1).strip()

                # Cell 1: Item Type (e.g. Prestable. Libros)
                item_type_raw = cells[1].get_text(" ", strip=True)
                item_type = re.sub(r"^Tipo de ejemplar\s*", "", item_type_raw, flags=re.IGNORECASE).strip()

                # Cell 2: Support (e.g. Libro)
                support_raw = cells[2].get_text(" ", strip=True)
                support = re.sub(r"^Soporte\s*", "", support_raw, flags=re.IGNORECASE).strip()

                # Cell 3: Availability & Loan Status
                disp_raw = cells[3].get_text(" ", strip=True)
                status_text = re.sub(r"^Disponibilidad\s*", "", disp_raw, flags=re.IGNORECASE).strip()

                is_available = False
                due_date = None

                if re.search(r"\bdisponible\b", status_text, re.IGNORECASE) and not re.search(r"despu[eé]s de|hasta|no disponible", status_text, re.IGNORECASE):
                    is_available = True
                    status_clean = "Disponible"
                else:
                    date_match = re.search(r"(\d{2}/\d{2}/\d{4})", status_text)
                    if date_match:
                        due_date = date_match.group(1)
                        status_clean = f"Prestado (hasta {due_date})"
                    else:
                        status_clean = status_text or "No disponible"

                holdings.append(
                    HoldingItem(
                        library=branch_name,
                        location=location or "General",
                        shelfmark=shelfmark or "N/A",
                        barcode=barcode,
                        item_type=item_type or "Prestable",
                        support=support or "Libro",
                        status_raw=status_clean,
                        is_available=is_available,
                        due_date=due_date,
                        lat=lat,
                        lon=lon,
                        district=district,
                        municipality=municipality,
                    )
                )

        return holdings

    def _parse_detail_page(self, html: str, doc_url: Optional[str] = None) -> BookResult:
        """Parses a full item detail page into a BookResult object."""
        soup = BeautifulSoup(html, "html.parser")

        meta_dict = {}
        for dt in soup.find_all("dt"):
            dd = dt.find_next_sibling("dd")
            if dd:
                label = dt.get_text(" ", strip=True).rstrip(":").strip()
                val = dd.get_text(" ", strip=True)
                if label not in meta_dict:
                    meta_dict[label] = val

        title = meta_dict.get("Título") or meta_dict.get("Titulo")
        if not title:
            heading = soup.find(["h1", "h2", "h3"], class_=lambda c: c and "docs_h" in c)
            title = heading.get_text(" ", strip=True) if heading else "Título no especificado"

        author = meta_dict.get("Autor/Autora") or meta_dict.get("Autor") or meta_dict.get("Autora")
        publication = meta_dict.get("Publicación") or meta_dict.get("Publicacion") or meta_dict.get("Lugar / ed. / año")
        year = meta_dict.get("Año") or meta_dict.get("Ano")
        if not year and publication:
            year_match = re.search(r"\b(19\d{2}|20\d{2})\b", publication)
            if year_match:
                year = year_match.group(1)

        edition = meta_dict.get("Edición") or meta_dict.get("Edicion")
        isbn = meta_dict.get("ISBN")
        description = meta_dict.get("Sumario, etc.") or meta_dict.get("Descripción física")

        holdings = self._parse_holdings_from_html(html)
        total_copies = len(holdings)
        available_copies = sum(1 for h in holdings if h.is_available)

        return BookResult(
            title=title,
            author=author,
            publication=publication,
            year=year,
            edition=edition,
            isbn=isbn,
            description=description,
            detail_url=doc_url,
            total_copies=total_copies,
            available_copies=available_copies,
            holdings=holdings,
        )

    def _parse_list_page(self, html: str, base_url: str) -> List[Tuple[dict, str]]:
        """Parses a multi-record search result list page and returns metadata and detail link URLs."""
        soup = BeautifulSoup(html, "html.parser")
        docs_info = soup.find_all("div", class_=lambda c: c and "c-docs_info" in c)
        results = []

        for doc in docs_info:
            link = doc.find("a", href=lambda h: h and "ACC=165" in h)
            if not link:
                continue

            rel_href = link["href"]
            detail_url = urllib.parse.urljoin(base_url, rel_href)

            author_el = doc.find("span", class_=lambda c: c and "c-docs_author" in c)
            title_el = doc.find("span", class_=lambda c: c and "c-docs_title" in c)
            title_rest_el = doc.find("span", class_=lambda c: c and "c-docs_titleRest" in c)

            author = author_el.get_text(" ", strip=True) if author_el else ""
            title_main = title_el.get_text(" ", strip=True) if title_el else ""
            title_rest = title_rest_el.get_text(" ", strip=True) if title_rest_el else ""
            full_title = f"{title_main} {title_rest}".rstrip("/").strip()

            dl = doc.find("dl")
            pub_info = ""
            if dl:
                pub_info = dl.get_text(" ", strip=True)

            meta = {
                "title": full_title or "Sin título",
                "author": author,
                "publication": pub_info,
            }
            results.append((meta, detail_url))

        return results

    def _apply_geospatial_grouping(
        self,
        books: List[BookResult],
        selected_libraries: List[str],
        radius_km: float,
    ) -> None:
        """Groups holdings in each BookResult into direct_matches, nearby_matches, and other_holdings."""
        if not selected_libraries:
            for book in books:
                book.direct_matches = []
                book.nearby_matches = []
                book.other_holdings = book.holdings
            return

        # Resolve coordinates for all user selected libraries
        selected_coords: List[Tuple[str, float, float]] = []
        for sel in selected_libraries:
            sel_geo = find_library_geo(sel)
            if not sel_geo and sel in MADRID_LIBRARIES_DB:
                sel_geo = MADRID_LIBRARIES_DB[sel]

            if sel_geo and sel_geo.get("lat") and sel_geo.get("lon"):
                selected_coords.append((sel_geo["name"], sel_geo["lat"], sel_geo["lon"]))

        norm_selected = [normalize_text(s) for s in selected_libraries]

        for book in books:
            direct_matches: List[HoldingItem] = []
            nearby_matches: List[HoldingItem] = []
            other_holdings: List[HoldingItem] = []

            for h in book.holdings:
                h_norm = normalize_text(h.library)

                # Check direct match
                is_direct = False
                for sel_n in norm_selected:
                    if sel_n in h_norm or h_norm in sel_n:
                        is_direct = True
                        break

                # Also match by ID if library geo info matches
                if not is_direct:
                    h_geo = find_library_geo(h.library)
                    if h_geo and (h_geo["id"] in selected_libraries or normalize_text(h_geo["name"]) in norm_selected):
                        is_direct = True

                if is_direct:
                    h.is_direct_match = True
                    h.distance_km = 0.0
                    direct_matches.append(h)
                    continue

                # If not direct match, check if within radius of any selected library
                if selected_coords and h.lat is not None and h.lon is not None:
                    min_dist = float("inf")
                    closest_ref_name = None

                    for ref_name, ref_lat, ref_lon in selected_coords:
                        dist = haversine_distance(h.lat, h.lon, ref_lat, ref_lon)
                        if dist < min_dist:
                            min_dist = dist
                            closest_ref_name = ref_name

                    if min_dist <= radius_km:
                        h.distance_km = min_dist
                        h.relative_to_library = closest_ref_name
                        nearby_matches.append(h)
                    else:
                        h.distance_km = min_dist if min_dist != float("inf") else None
                        h.relative_to_library = closest_ref_name
                        other_holdings.append(h)
                else:
                    other_holdings.append(h)

            # Sort nearby_matches by distance ascending
            nearby_matches.sort(key=lambda item: (item.distance_km if item.distance_km is not None else 9999, not item.is_available))

            book.direct_matches = direct_matches
            book.nearby_matches = nearby_matches
            book.other_holdings = other_holdings

    async def search(
        self,
        title: Optional[str] = None,
        author: Optional[str] = None,
        max_items: int = 5,
        selected_libraries: Optional[List[str]] = None,
        radius_km: float = 3.0,
    ) -> SearchResponse:
        """Executes search and returns parsed books with live branch holdings and geospatial grouping."""
        title = (title or "").strip()
        author = (author or "").strip()
        selected_libraries = selected_libraries or []

        if not title and not author:
            return SearchResponse(
                success=False,
                outcome="invalid_query",
                error="Debe especificar al menos un título o un autor para buscar.",
            )

        async with httpx.AsyncClient(headers=self.headers, follow_redirects=True, timeout=self.timeout) as client:
            try:
                session_url, action_url = await self._init_session(client)
            except Exception as e:
                logger.error(f"Failed to initialize AbsysNet session: {e}", exc_info=True)
                return SearchResponse(
                    success=False,
                    query_title=title,
                    query_author=author,
                    selected_libraries=selected_libraries,
                    radius_km=radius_km,
                    outcome="catalog_unavailable",
                    error=f"No se pudo conectar con el catálogo de bibliotecas: {str(e)}",
                )

            # Clean and sanitize input parameters
            clean_title = re.sub(r"\s+", " ", title).strip()
            # Replace dots in author initials (e.g. "J.K. Rowling" -> "J K Rowling") for AbsysNet index compatibility
            clean_author = re.sub(r"\.+", " ", author)
            clean_author = re.sub(r"\s+", " ", clean_author).strip()

            # Build query payload for Form 2 (Advanced Search)
            if not clean_title and clean_author:
                # Author-only search: configure field selector to Author (4)
                payload = {
                    "ACC": "131",
                    "START": "1",
                    "FORM": "2",
                    "xsqf01": "",
                    "subcat": "/",
                    "xsnf12": "4",  # Select field: Autor
                    "xsqf12": clean_author,
                    "xsqf03": clean_author,
                    "xsnlis": "10",
                    "xssort": "55088864",  # Relevance
                }
            elif clean_title and not clean_author:
                # Title-only search: configure field selector to Title (0)
                payload = {
                    "ACC": "131",
                    "START": "1",
                    "FORM": "2",
                    "xsqf01": "",
                    "subcat": "/",
                    "xsnf12": "0",  # Select field: Título
                    "xsqf12": clean_title,
                    "xsqf03": "",
                    "xsnlis": "10",
                    "xssort": "55088864",
                }
            else:
                # Both Title and Author
                payload = {
                    "ACC": "131",
                    "START": "1",
                    "FORM": "2",
                    "xsqf01": "",
                    "subcat": "/",
                    "xsnf12": "0",  # Title in main selector
                    "xsqf12": clean_title,
                    "xsqf03": clean_author,  # Author in author field
                    "xsnlis": "10",
                    "xssort": "55088864",
                }

            try:
                resp_search = await client.post(action_url, data=payload, timeout=self.timeout)
                resp_search.raise_for_status()
            except Exception as e:
                logger.error(f"Failed to submit search query: {e}", exc_info=True)
                return SearchResponse(
                    success=False,
                    query_title=title,
                    query_author=author,
                    selected_libraries=selected_libraries,
                    radius_km=radius_km,
                    outcome="catalog_unavailable",
                    error=f"Error al enviar la consulta al catálogo: {str(e)}",
                )

            search_html = resp_search.text
            final_search_url = str(resp_search.url)

            soup = BeautifulSoup(search_html, "html.parser")
            docs_info = soup.find_all("div", class_=lambda c: c and "c-docs_info" in c)

            # If author search returned no results, attempt fallback with keyword search (xsqf01)
            if not docs_info and clean_author and not clean_title:
                try:
                    fallback_payload = {
                        "ACC": "131",
                        "START": "1",
                        "FORM": "2",
                        "xsqf01": clean_author,
                        "subcat": "/",
                        "xsnlis": "10",
                        "xssort": "55088864",
                    }
                    resp_fallback = await client.post(action_url, data=fallback_payload, timeout=self.timeout)
                    if resp_fallback.status_code == 200:
                        search_html = resp_fallback.text
                        final_search_url = str(resp_fallback.url)
                        soup = BeautifulSoup(search_html, "html.parser")
                        docs_info = soup.find_all("div", class_=lambda c: c and "c-docs_info" in c)
                except Exception as fb_err:
                    logger.warning(f"Author fallback query error: {fb_err}")

            no_results_indicator = (
                soup.find(string=re.compile(r"NO recupera resultados|no se han encontrado|0 docs\.", re.IGNORECASE))
                or "NO recupera resultados" in search_html
            )
            if no_results_indicator:
                return SearchResponse(
                    success=True,
                    outcome="no_results",
                    query_title=title,
                    query_author=author,
                    selected_libraries=selected_libraries,
                    radius_km=radius_km,
                    total_editions=0,
                    total_copies=0,
                    total_available_copies=0,
                    results=[],
                )

            has_bib_fields = bool(soup.find("dt", string=re.compile(r"T[íi]tulo", re.IGNORECASE)))
            has_copies_table = bool(soup.find("td", class_=lambda c: c and "copias_tableDisp" in c) or soup.find(class_=lambda c: c and "js-evn-copiasDetail-indexSign" in c))

            # 1. Single Result -> Direct Detail Page
            if (has_bib_fields or has_copies_table) and not docs_info:
                book = self._parse_detail_page(search_html, final_search_url)
                if book.title and book.title != "Título no especificado":
                    self._apply_geospatial_grouping([book], selected_libraries, radius_km)
                    return SearchResponse(
                        success=True,
                        query_title=title,
                        query_author=author,
                        selected_libraries=selected_libraries,
                        radius_km=radius_km,
                        total_editions=1,
                        total_copies=book.total_copies,
                        total_available_copies=book.available_copies,
                        results=[book],
                    )

            # 2. No Results fallback. None of the known markers (or a record without a title) means the
            # markup changed: flagged as catalog_unavailable so it is never shown as "not in catalog".
            if not docs_info:
                return SearchResponse(
                    success=True,
                    outcome="catalog_unavailable",
                    error=(
                        "Ficha del catálogo sin título reconocible"
                        if has_bib_fields or has_copies_table
                        else "El catálogo devolvió una página no reconocida"
                    ),
                    query_title=title,
                    query_author=author,
                    selected_libraries=selected_libraries,
                    radius_km=radius_km,
                    total_editions=0,
                    total_copies=0,
                    total_available_copies=0,
                    results=[],
                )

            # 3. Multi-Record Result List Page
            items_meta = self._parse_list_page(search_html, final_search_url)
            if not items_meta:
                return SearchResponse(
                    success=True,
                    outcome="catalog_unavailable",
                    error="El catálogo devolvió una página no reconocida",
                    query_title=title,
                    query_author=author,
                    selected_libraries=selected_libraries,
                    radius_km=radius_km,
                    results=[],
                )
            selected_items = items_meta[:max_items]
            failed_details: List[str] = []

            async def fetch_item_detail(meta: dict, detail_url: str) -> BookResult:
                try:
                    res = await client.get(detail_url, timeout=self.timeout)
                    if res.status_code == 200:
                        book = self._parse_detail_page(res.text, detail_url)
                        if not book.title or book.title == "Título no especificado":
                            book.title = meta.get("title", "Sin título")
                        if not book.author:
                            book.author = meta.get("author")
                        return book
                except Exception as ex:
                    logger.warning(f"Error fetching detail for {detail_url}: {ex}")

                failed_details.append(detail_url)
                return BookResult(
                    title=meta.get("title", "Sin título"),
                    author=meta.get("author"),
                    publication=meta.get("publication"),
                    detail_url=detail_url,
                    total_copies=0,
                    available_copies=0,
                    holdings=[],
                )

            tasks = [fetch_item_detail(meta, url) for meta, url in selected_items]
            books = await asyncio.gather(*tasks)

            if len(failed_details) == len(books):
                return SearchResponse(
                    success=True,
                    outcome="catalog_unavailable",
                    error="No se pudieron cargar las fichas del catálogo",
                    query_title=title,
                    query_author=author,
                    selected_libraries=selected_libraries,
                    radius_km=radius_km,
                    results=[],
                )

            self._apply_geospatial_grouping(books, selected_libraries, radius_km)

            total_copies = sum(b.total_copies for b in books)
            total_available = sum(b.available_copies for b in books)

            return SearchResponse(
                success=True,
                query_title=title,
                query_author=author,
                selected_libraries=selected_libraries,
                radius_km=radius_km,
                total_editions=len(items_meta),
                total_copies=total_copies,
                total_available_copies=total_available,
                results=books,
                is_partial=bool(failed_details),
            )
