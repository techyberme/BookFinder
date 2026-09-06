"""API endpoint tests for Madrid Public Libraries Book Finder & PWA Endpoints."""

import pytest
from httpx import AsyncClient, ASGITransport
from backend.main import app


@pytest.mark.asyncio
async def test_health_check():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/api/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"


@pytest.mark.asyncio
async def test_pwa_manifest_and_sw():
    """Verify PWA manifest and service worker are served at root scope."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Manifest
        resp = await client.get("/manifest.json")
        assert resp.status_code == 200
        manifest = resp.json()
        assert manifest["name"] == "Zahorí - Buscador de Libros"
        assert manifest["short_name"] == "Zahorí"
        assert manifest["display"] == "standalone"
        assert len(manifest["icons"]) >= 2

        # Service Worker
        resp_sw = await client.get("/service-worker.js")
        assert resp_sw.status_code == 200
        assert "Service-Worker-Allowed" in resp_sw.headers
        assert "zahori-shell" in resp_sw.text


@pytest.mark.asyncio
async def test_get_libraries_endpoint():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/api/libraries")
        assert resp.status_code == 200
        data = resp.json()
        assert "libraries" in data
        assert len(data["libraries"]) >= 20
        assert any(l["id"] == "eugenio_trias" for l in data["libraries"])


@pytest.mark.asyncio
async def test_search_missing_parameters():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/api/search")
        assert resp.status_code == 400
        assert "Debe proporcionar al menos un título o un autor" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_search_live_api_with_geo_filters():
    """Live API search integration test with selected libraries and radius."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/api/search?title=Ficciones&author=Borges&limit=1&selected_libraries=eugenio_trias&radius_km=5.0")
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["total_editions"] >= 1
        assert len(data["results"]) >= 1
        book = data["results"][0]
        assert "Ficciones" in book["title"]
        assert "direct_matches" in book
        assert "nearby_matches" in book
        assert "other_holdings" in book


@pytest.mark.asyncio
async def test_goodreads_shelf_endpoint():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/api/goodreads/shelf?user_id=177587843&shelf=to-read")
        # Either 200 (if Goodreads reachable) or 404/502 (if network/rate limited)
        assert resp.status_code in [200, 404, 502]
        if resp.status_code == 200:
            data = resp.json()
            assert data["success"] is True
            assert "books" in data


@pytest.mark.asyncio
async def test_batch_availability_api():
    """Test batch availability endpoint with sample books."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        payload = {
            "books": [
                {"book_id": "b1", "title": "Cien años de soledad", "author": "García Márquez"},
                {"book_id": "b2", "title": "Ficciones", "author": "Borges"},
            ],
            "selected_libraries": ["eugenio_trias"],
            "radius_km": 5.0,
            "limit_per_book": 1,
        }
        resp = await client.post("/api/check-batch-availability", json=payload)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["total_checked"] == 2
        assert len(data["results"]) == 2
        assert any(r["title"] == "Cien años de soledad" for r in data["results"])


@pytest.mark.asyncio
async def test_recommendations_endpoint():
    """Test recommendations endpoint with candidate books."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        payload = {
            "books": [
                {"book_id": "b1", "title": "Cien años de soledad", "author": "García Márquez"},
                {"book_id": "b2", "title": "Ficciones", "author": "Borges"},
                {"book_id": "b3", "title": "El Quijote", "author": "Cervantes"},
            ],
            "selected_libraries": ["eugenio_trias"],
            "radius_km": 5.0,
            "target_count": 2,
        }
        resp = await client.post("/api/goodreads/recommendations", json=payload)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["found_count"] >= 1
        assert len(data["recommendations"]) >= 1
        assert data["recommendations"][0]["is_available"] is True
