"""Unit tests for Madrid libraries geospatial lookup and Haversine distance calculations."""

import pytest
from backend.madrid_libraries_geo import (
    haversine_distance,
    find_library_geo,
    normalize_text,
    get_all_libraries_list,
    MADRID_LIBRARIES_DB,
)
from backend.scraper import AbsysNetScraper
from backend.models import BookResult, HoldingItem


def test_haversine_distance():
    # Distance between Puerta del Sol (40.4168, -3.7038) and Retiro / Eugenio Trias (40.4158, -3.6791) is ~2.1 km
    d = haversine_distance(40.4168, -3.7038, 40.4158, -3.6791)
    assert 1.9 <= d <= 2.3

    # Distance to same point is 0.0
    assert haversine_distance(40.4358, -3.6667, 40.4358, -3.6667) == 0.0


def test_find_library_geo():
    # Test normalized match for typical AbsysNet strings
    geo1 = find_library_geo("CARABANCHEL. BP La Chata")
    assert geo1 is not None
    assert geo1["id"] == "la_chata"
    assert geo1["district"] == "Carabanchel"

    geo2 = find_library_geo("José Luis Sampedro")
    assert geo2 is not None
    assert geo2["id"] == "jose_luis_sampedro"
    assert geo2["district"] == "Chamberí"

    geo3 = find_library_geo("RETIRO. BP Eugenio Trías")
    assert geo3 is not None
    assert geo3["id"] == "eugenio_trias"

    geo4 = find_library_geo("CHAMARTÍN. BP Dámaso Alonso")
    assert geo4 is not None
    assert geo4["id"] == "damaso_alonso"

    geo5 = find_library_geo("MONCLOA-ARAVACA. BP Acuña")
    assert geo5 is not None
    assert geo5["id"] == "jose_acuna"
    assert geo5["district"] == "Moncloa-Aravaca"

    geo6 = find_library_geo("Biblioteca Pública José Acuña")
    assert geo6 is not None
    assert geo6["id"] == "jose_acuna"


def test_get_all_libraries_list():
    libs = get_all_libraries_list()
    assert len(libs) >= 20
    assert any(l["id"] == "eugenio_trias" for l in libs)
    assert all("lat" in l and "lon" in l for l in libs)


def test_apply_geospatial_grouping():
    scraper = AbsysNetScraper()

    # Create dummy book result with copies in Eugenio Trias (Retiro) and Manuel Alvar (Salamanca ~2.4km away) and Alcorcon (~16km away)
    h_trias = HoldingItem(
        library="RETIRO. BP Eugenio Trías",
        location="Sala adultos",
        shelfmark="N TEST",
        status_raw="Prestado (hasta 10/09/2026)",
        is_available=False,
        lat=40.4158,
        lon=-3.6791,
    )
    h_alvar = HoldingItem(
        library="SALAMANCA. BP Manuel Alvar",
        location="Sala adultos",
        shelfmark="N TEST",
        status_raw="Disponible",
        is_available=True,
        lat=40.4358,
        lon=-3.6667,
    )
    h_alcorcon = HoldingItem(
        library="Biblioteca Municipal de Alcorcón",
        location="Sala adultos",
        shelfmark="N TEST",
        status_raw="Disponible",
        is_available=True,
        lat=40.3478,
        lon=-3.8291,
    )

    book = BookResult(
        title="Test Book",
        author="Author",
        holdings=[h_trias, h_alvar, h_alcorcon],
    )

    # User selected "eugenio_trias" with radius 5.0 km
    scraper._apply_geospatial_grouping([book], selected_libraries=["eugenio_trias"], radius_km=5.0)

    # Direct match should be Eugenio Trias
    assert len(book.direct_matches) == 1
    assert "Eugenio" in book.direct_matches[0].library
    assert book.direct_matches[0].is_direct_match is True

    # Nearby match should be Manuel Alvar (~2.4 km <= 5.0 km)
    assert len(book.nearby_matches) == 1
    assert "Manuel Alvar" in book.nearby_matches[0].library
    assert book.nearby_matches[0].distance_km is not None
    assert book.nearby_matches[0].distance_km < 5.0

    # Other holdings should be Alcorcón (> 5.0 km)
    assert len(book.other_holdings) == 1
    assert "Alcorcón" in book.other_holdings[0].library
