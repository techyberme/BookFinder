"""Unit and integration tests for AbsysNet scraper."""

import pytest
from backend.scraper import AbsysNetScraper
from backend.models import SearchResponse, BookResult, HoldingItem


SAMPLE_DETAIL_HTML = """
<!DOCTYPE html>
<html>
<head><title>Detalle</title></head>
<body>
  <dl>
    <dt>Título:</dt><dd>Cien años de soledad / Gabriel García Márquez</dd>
    <dt>Autor/Autora:</dt><dd>García Márquez, Gabriel (1927-2014)</dd>
    <dt>Publicación:</dt><dd>Barcelona : Random House, 2024</dd>
    <dt>Año:</dt><dd>2024</dd>
    <dt>ISBN:</dt><dd>978-84-663-7353-1</dd>
  </dl>

  <div class="c-accordion_item">
    <button class="c-accordion_btn">Sucursal: CARABANCHEL. BP La Chata</button>
    <table>
      <tr><th>Localización / Signatura</th><th>Tipo de ejemplar</th><th>Soporte</th><th>Disponibilidad</th></tr>
      <tr>
        <td>
          <span class="icm_locSign">Sala adultos</span>
          <a class="js-evn-copiasDetail-indexSign" data-bc="1402046226" data-sign="N GAR cie">N GAR cie</a>
        </td>
        <td>Prestable. Libros</td>
        <td>Libro</td>
        <td class="copias_tableDisp">Disponible</td>
      </tr>
    </table>
  </div>

  <div class="c-accordion_item">
    <button class="c-accordion_btn">Sucursal: CHAMARTÍN. BP Dámaso Alonso</button>
    <table>
      <tr><th>Localización / Signatura</th><th>Tipo de ejemplar</th><th>Soporte</th><th>Disponibilidad</th></tr>
      <tr>
        <td>
          <span class="icm_locSign">Depósito</span>
          <a class="js-evn-copiasDetail-indexSign" data-bc="1402099999" data-sign="N GAR cie">N GAR cie</a>
        </td>
        <td>Prestable. Libros</td>
        <td>Libro</td>
        <td class="copias_tableDisp">Disponible después de 15/09/2026</td>
      </tr>
    </table>
  </div>
</body>
</html>
"""


def test_parse_holdings_from_html():
    scraper = AbsysNetScraper()
    holdings = scraper._parse_holdings_from_html(SAMPLE_DETAIL_HTML)

    assert len(holdings) == 2

    # First copy: Available
    assert holdings[0].library == "CARABANCHEL. BP La Chata"
    assert holdings[0].location == "Sala adultos"
    assert holdings[0].shelfmark == "N GAR cie"
    assert holdings[0].barcode == "1402046226"
    assert holdings[0].is_available is True
    assert holdings[0].due_date is None

    # Second copy: On loan until 15/09/2026
    assert holdings[1].library == "CHAMARTÍN. BP Dámaso Alonso"
    assert holdings[1].location == "Depósito"
    assert holdings[1].shelfmark == "N GAR cie"
    assert holdings[1].is_available is False
    assert holdings[1].due_date == "15/09/2026"
    assert "Prestado" in holdings[1].status_raw


def test_parse_detail_page():
    scraper = AbsysNetScraper()
    book = scraper._parse_detail_page(SAMPLE_DETAIL_HTML, doc_url="http://example.com/doc1")

    assert "Cien años de soledad" in book.title
    assert "García Márquez" in book.author
    assert book.year == "2024"
    assert book.isbn == "978-84-663-7353-1"
    assert book.total_copies == 2
    assert book.available_copies == 1
    assert len(book.holdings) == 2


@pytest.mark.asyncio
async def test_live_search_cien_anos():
    """Live search test against the Madrid AbsysNet OPAC."""
    scraper = AbsysNetScraper(timeout=25.0)
    response = await scraper.search(title="Cien años de soledad", author="García Márquez", max_items=2)

    assert response.success is True
    assert response.total_editions > 0
    assert len(response.results) > 0

    first_book = response.results[0]
    assert "Cien años de soledad" in first_book.title
    assert len(first_book.holdings) > 0
    assert any(h.is_available for h in first_book.holdings)


@pytest.mark.asyncio
async def test_live_search_no_results():
    """Live search test for non-existent title."""
    scraper = AbsysNetScraper(timeout=25.0)
    response = await scraper.search(title="xkqw7899zznonexistenttitle9999", max_items=2)

    assert response.success is True
    assert response.total_editions == 0
    assert len(response.results) == 0


@pytest.mark.asyncio
async def test_live_search_author_only():
    """Live search test for author only (e.g., J.K. Rowling and Irene Vallejo)."""
    scraper = AbsysNetScraper(timeout=25.0)
    response = await scraper.search(author="J.K. Rowling", max_items=2)

    assert response.success is True
    assert response.total_editions > 0
    assert len(response.results) > 0
    assert any("Rowling" in (b.author or "") for b in response.results)
