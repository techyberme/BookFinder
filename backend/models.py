"""Data models for Madrid Public Libraries (AbsysNet) search results, geospatial matching, and Goodreads batch checks."""

from typing import List, Optional
from pydantic import BaseModel, Field


class HoldingItem(BaseModel):
    """Represents a specific physical or digital copy of a book in a library branch."""
    library: str = Field(..., description="Library or branch name (e.g., 'CARABANCHEL. BP La Chata')")
    location: Optional[str] = Field(None, description="Location within the library (e.g., 'Sala adultos', 'Depósito')")
    shelfmark: Optional[str] = Field(None, description="Signatura / shelf mark code (e.g., 'N GAR cie')")
    barcode: Optional[str] = Field(None, description="Barcode identifier (BC)")
    item_type: Optional[str] = Field(None, description="Type of copy (e.g., 'Prestable. Libros')")
    support: Optional[str] = Field(None, description="Media format (e.g., 'Libro')")
    status_raw: str = Field(..., description="Raw availability text from OPAC")
    is_available: bool = Field(..., description="True if immediately available for loan")
    due_date: Optional[str] = Field(None, description="Expected return date if currently on loan (DD/MM/YYYY)")
    
    # Geospatial annotations
    lat: Optional[float] = Field(None, description="Latitude of branch")
    lon: Optional[float] = Field(None, description="Longitude of branch")
    district: Optional[str] = Field(None, description="District or neighborhood")
    municipality: Optional[str] = Field(None, description="Municipality name")
    distance_km: Optional[float] = Field(None, description="Distance in km to closest selected library")
    relative_to_library: Optional[str] = Field(None, description="Name of the selected library this distance is measured from")
    is_direct_match: bool = Field(False, description="True if this holding belongs to a user-selected library")


class BookResult(BaseModel):
    """Represents a bibliographic record (edition) with its associated library holdings."""
    doc_id: Optional[str] = Field(None, description="Internal OPAC document index or record number")
    title: str = Field(..., description="Book title")
    author: Optional[str] = Field(None, description="Author / creators")
    publication: Optional[str] = Field(None, description="Publisher & publication place")
    year: Optional[str] = Field(None, description="Publication year")
    edition: Optional[str] = Field(None, description="Edition statement")
    isbn: Optional[str] = Field(None, description="ISBN if present")
    description: Optional[str] = Field(None, description="Summary or physical description")
    detail_url: Optional[str] = Field(None, description="Direct URL to OPAC record")
    total_copies: int = Field(0, description="Total number of physical copies registered")
    available_copies: int = Field(0, description="Number of copies currently available on shelf")
    
    # Holdings buckets
    holdings: List[HoldingItem] = Field(default_factory=list, description="All physical holdings across branches")
    direct_matches: List[HoldingItem] = Field(default_factory=list, description="Holdings in specifically selected libraries")
    nearby_matches: List[HoldingItem] = Field(default_factory=list, description="Holdings in branches within proximity radius with available copies")
    other_holdings: List[HoldingItem] = Field(default_factory=list, description="Remaining holdings outside radius or unselected")


class SearchResponse(BaseModel):
    """API response model for book search with proximity recommendations."""
    success: bool = True
    query_title: Optional[str] = None
    query_author: Optional[str] = None
    selected_libraries: List[str] = Field(default_factory=list)
    radius_km: Optional[float] = None
    total_editions: int = 0
    total_copies: int = 0
    total_available_copies: int = 0
    results: List[BookResult] = Field(default_factory=list)
    error: Optional[str] = None


# --- Batch & Goodreads Models ---

class BatchBookQuery(BaseModel):
    """Input item for batch availability queries."""
    book_id: Optional[str] = None
    title: str
    author: Optional[str] = None
    isbn: Optional[str] = None
    cover_image_url: Optional[str] = None


class BatchAvailabilityRequest(BaseModel):
    """Payload for batch checking a list of books."""
    books: List[BatchBookQuery] = Field(..., max_length=50)
    selected_libraries: Optional[List[str]] = Field(default_factory=list)
    radius_km: float = 3.0
    limit_per_book: int = 2


class BatchBookAvailabilityResult(BaseModel):
    """Availability status summary for a single book in a batch check."""
    book_id: Optional[str] = None
    title: str
    author: Optional[str] = None
    cover_image_url: Optional[str] = None
    is_available: bool = False
    total_editions: int = 0
    total_copies: int = 0
    total_available_copies: int = 0
    status_summary: str = "No disponible"
    best_match_library: Optional[str] = None
    best_match_distance_km: Optional[float] = None
    direct_matches_count: int = 0
    direct_matches_available: int = 0
    full_result: Optional[BookResult] = None


class BatchAvailabilityResponse(BaseModel):
    """Response model for batch availability verification."""
    success: bool = True
    total_checked: int = 0
    total_available_books: int = 0
    results: List[BatchBookAvailabilityResult] = Field(default_factory=list)
    error: Optional[str] = None


class RecommendationsRequest(BaseModel):
    """Payload for finding available recommended books from a shelf."""
    books: List[BatchBookQuery] = Field(..., max_length=100)
    selected_libraries: Optional[List[str]] = Field(default_factory=list)
    radius_km: float = 3.0
    target_count: int = 2


class RecommendationsResponse(BaseModel):
    """Response model containing available recommended books."""
    success: bool = True
    found_count: int = 0
    recommendations: List[BatchBookAvailabilityResult] = Field(default_factory=list)
    error: Optional[str] = None
