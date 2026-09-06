"""FastAPI backend application for Madrid Public Libraries Book Availability & Goodreads Integration."""

import asyncio
import logging
import random
import sys
from pathlib import Path
from typing import List, Optional

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .models import (
    SearchResponse,
    BatchAvailabilityRequest,
    BatchAvailabilityResponse,
    BatchBookAvailabilityResult,
    RecommendationsRequest,
    RecommendationsResponse,
)
from .scraper import AbsysNetScraper
from .madrid_libraries_geo import get_all_libraries_list
from .goodreads_service import (
    fetch_goodreads_shelf,
    clean_book_title_for_search,
    extract_goodreads_user_id,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("bookfinder")

app = FastAPI(
    title="Madrid Public Libraries Book Finder API",
    description="Real-time availability search across Madrid Public Libraries Network with geospatial recommendations and Goodreads shelf synchronization",
    version="1.4.0",
)

# Enable CORS and GZip for high-performance mobile network delivery
app.add_middleware(GZipMiddleware, minimum_size=1000)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Scraper instance
scraper = AbsysNetScraper(timeout=20.0)

# Base directories (support PyInstaller _MEIPASS bundle and standard directory execution)
if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
    BASE_DIR = Path(sys._MEIPASS)
else:
    BASE_DIR = Path(__file__).resolve().parent.parent

FRONTEND_DIR = BASE_DIR / "frontend"


@app.get("/api/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "ok", "service": "Madrid Public Libraries Book Finder"}


@app.get("/api/libraries")
async def get_libraries():
    """Returns the master list of Madrid Public Libraries with geographic and district coordinates."""
    return {"libraries": get_all_libraries_list()}


@app.get("/api/search", response_model=SearchResponse)
async def search_books(
    title: Optional[str] = Query(None, description="Title or keywords to search in book title"),
    author: Optional[str] = Query(None, description="Author / creator name"),
    limit: int = Query(5, ge=1, le=10, description="Max number of matching editions to fetch detailed holdings for"),
    selected_libraries: Optional[List[str]] = Query(None, description="List of preferred library IDs or branch names"),
    radius_km: float = Query(3.0, ge=0.5, le=50.0, description="Proximity radius in km for nearby library recommendations"),
):
    """
    Search the Madrid Public Libraries Network for book titles/authors and retrieve live holdings
    with direct matches in preferred libraries and nearby alternative recommendations.
    """
    title_clean = (title or "").strip()
    author_clean = (author or "").strip()

    if not title_clean and not author_clean:
        raise HTTPException(
            status_code=400,
            detail="Debe proporcionar al menos un título o un autor en los parámetros de búsqueda.",
        )

    # Process selected_libraries: handle comma-separated elements in query
    parsed_selected_libs: List[str] = []
    if selected_libraries:
        for item in selected_libraries:
            if "," in item:
                parsed_selected_libs.extend([s.strip() for s in item.split(",") if s.strip()])
            elif item.strip():
                parsed_selected_libs.append(item.strip())

    try:
        response = await scraper.search(
            title=title_clean,
            author=author_clean,
            max_items=limit,
            selected_libraries=parsed_selected_libs,
            radius_km=radius_km,
        )
        return response
    except Exception as e:
        logger.error(f"Search endpoint error: {e}", exc_info=True)
        raise HTTPException(
            status_code=502,
            detail=f"Error al interactuar con el catálogo de bibliotecas: {str(e)}",
        )


@app.get("/api/goodreads/shelf")
async def get_goodreads_shelf(
    user_id: str = Query(..., description="Goodreads User ID, Profile URL, or RSS link"),
    shelf: str = Query("to-read", description="Goodreads shelf name (e.g. 'to-read', 'read', 'currently-reading')"),
):
    """
    Fetches and parses a public Goodreads user shelf via XML/RSS feed with sanitized titles for search.
    """
    clean_id = extract_goodreads_user_id(user_id)
    if not clean_id:
        raise HTTPException(status_code=400, detail="Identificador de usuario de Goodreads no válido.")

    try:
        books, user_name = await fetch_goodreads_shelf(user_id, shelf=shelf)
        return {
            "success": True,
            "user_id": clean_id,
            "user_name": user_name,
            "shelf": shelf,
            "total_books": len(books),
            "books": [b.model_dump() for b in books],
        }
    except ValueError as val_err:
        raise HTTPException(status_code=404, detail=str(val_err))
    except Exception as err:
        logger.error(f"Goodreads shelf retrieval error: {err}", exc_info=True)
        raise HTTPException(status_code=502, detail=f"Error al obtener estantería de Goodreads: {str(err)}")


async def _check_single_book_availability(
    item,
    selected_libraries: Optional[List[str]],
    radius_km: float,
    limit_per_book: int = 2,
    semaphore: Optional[asyncio.Semaphore] = None,
) -> BatchBookAvailabilityResult:
    """Helper to check live catalog availability for a single book query item."""
    search_title = clean_book_title_for_search(item.title)
    
    async def do_search():
        try:
            search_res = await scraper.search(
                title=search_title,
                author=item.author,
                max_items=limit_per_book,
                selected_libraries=selected_libraries,
                radius_km=radius_km,
            )

            if not search_res.success or not search_res.results:
                return BatchBookAvailabilityResult(
                    book_id=item.book_id,
                    title=item.title,
                    author=item.author,
                    cover_image_url=item.cover_image_url,
                    is_available=False,
                    total_editions=0,
                    total_copies=0,
                    total_available_copies=0,
                    status_summary="No encontrado en catálogo",
                )

            all_holdings = []
            direct_matches = []
            nearby_matches = []
            for b in search_res.results:
                all_holdings.extend(b.holdings)
                direct_matches.extend(b.direct_matches)
                nearby_matches.extend(b.nearby_matches)

            total_avail = sum(1 for h in all_holdings if h.is_available)
            total_copies = len(all_holdings)
            is_available = total_avail > 0

            direct_avail = sum(1 for h in direct_matches if h.is_available)

            best_lib = None
            best_dist = None

            if direct_avail > 0:
                avail_direct = [h for h in direct_matches if h.is_available]
                best_lib = avail_direct[0].library
                best_dist = 0.0
                summary = f"Disponible en {best_lib}"
            elif len(direct_matches) > 0 and not is_available:
                summary = f"Prestado en {direct_matches[0].library}"
            elif nearby_matches and any(h.is_available for h in nearby_matches):
                avail_nearby = [h for h in nearby_matches if h.is_available]
                best_lib = avail_nearby[0].library
                best_dist = avail_nearby[0].distance_km
                summary = f"Disponible en {best_lib} (a {best_dist:.1f} km)"
            elif is_available:
                avail_any = [h for h in all_holdings if h.is_available]
                best_lib = avail_any[0].library
                summary = f"Disponible en {best_lib}"
            elif total_copies > 0:
                summary = f"Prestado ({total_copies} ejemplares en red)"
            else:
                summary = "No disponible"

            return BatchBookAvailabilityResult(
                book_id=item.book_id,
                title=item.title,
                author=item.author,
                cover_image_url=item.cover_image_url,
                is_available=is_available,
                total_editions=search_res.total_editions,
                total_copies=total_copies,
                total_available_copies=total_avail,
                status_summary=summary,
                best_match_library=best_lib,
                best_match_distance_km=best_dist,
                direct_matches_count=len(direct_matches),
                direct_matches_available=direct_avail,
                full_result=search_res.results[0] if search_res.results else None,
            )

        except Exception as e:
            logger.warning(f"Error batch checking '{item.title}': {e}")
            return BatchBookAvailabilityResult(
                book_id=item.book_id,
                title=item.title,
                author=item.author,
                cover_image_url=item.cover_image_url,
                is_available=False,
                status_summary=f"Error: {str(e)[:40]}",
            )

    if semaphore:
        async with semaphore:
            return await do_search()
    return await do_search()


@app.post("/api/check-batch-availability", response_model=BatchAvailabilityResponse)
async def check_batch_availability(request: BatchAvailabilityRequest):
    """
    Batch checks availability for a list of books against the Madrid Public Libraries catalog.
    Uses bounded concurrency (max 3 parallel requests) to avoid overwhelming OPAC servers.
    """
    if not request.books:
        return BatchAvailabilityResponse(total_checked=0, total_available_books=0, results=[])

    semaphore = asyncio.Semaphore(3)
    tasks = [
        _check_single_book_availability(
            b,
            selected_libraries=request.selected_libraries,
            radius_km=request.radius_km,
            limit_per_book=request.limit_per_book,
            semaphore=semaphore,
        )
        for b in request.books
    ]
    results = await asyncio.gather(*tasks)

    total_avail_count = sum(1 for r in results if r.is_available)

    return BatchAvailabilityResponse(
        success=True,
        total_checked=len(results),
        total_available_books=total_avail_count,
        results=results,
    )


@app.post("/api/goodreads/recommendations", response_model=RecommendationsResponse)
async def get_shelf_recommendations(request: RecommendationsRequest):
    """
    Samples books from a shelf and queries the catalog until `target_count` available books are found.
    Returns the recommended available books with their pickup library annotations.
    """
    if not request.books:
        return RecommendationsResponse(found_count=0, recommendations=[])

    candidates = list(request.books)
    random.shuffle(candidates)

    found_recommendations: List[BatchBookAvailabilityResult] = []
    semaphore = asyncio.Semaphore(3)

    # Process candidates in small batches until finding target_count available books
    batch_size = 3
    for i in range(0, len(candidates), batch_size):
        if len(found_recommendations) >= request.target_count:
            break

        chunk = candidates[i : i + batch_size]
        tasks = [
            _check_single_book_availability(
                b,
                selected_libraries=request.selected_libraries,
                radius_km=request.radius_km,
                limit_per_book=1,
                semaphore=semaphore,
            )
            for b in chunk
        ]
        chunk_results = await asyncio.gather(*tasks)

        for res in chunk_results:
            if res.is_available:
                found_recommendations.append(res)
                if len(found_recommendations) >= request.target_count:
                    break

    return RecommendationsResponse(
        success=True,
        found_count=len(found_recommendations),
        recommendations=found_recommendations[: request.target_count],
    )


# Mount frontend files & PWA endpoints
if FRONTEND_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(FRONTEND_DIR)), name="static")

    @app.get("/manifest.json")
    async def serve_manifest():
        """Serves the PWA manifest at the root scope."""
        manifest_file = FRONTEND_DIR / "manifest.json"
        if manifest_file.exists():
            return FileResponse(str(manifest_file), media_type="application/manifest+json")
        raise HTTPException(status_code=404, detail="Manifest not found")

    @app.get("/service-worker.js")
    async def serve_service_worker():
        """Serves the Service Worker at root scope."""
        sw_file = FRONTEND_DIR / "service-worker.js"
        if sw_file.exists():
            return FileResponse(
                str(sw_file),
                media_type="application/javascript",
                headers={"Service-Worker-Allowed": "/"},
            )
        raise HTTPException(status_code=404, detail="Service worker not found")

    @app.get("/")
    async def serve_index():
        """Serves the Single Page Application."""
        index_file = FRONTEND_DIR / "index.html"
        if index_file.exists():
            return FileResponse(str(index_file))
        return {"message": "Frontend index.html not found."}
