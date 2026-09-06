"""Goodreads RSS shelf parser and title normalization service."""

import logging
import re
import xml.etree.ElementTree as ET
from typing import List, Optional, Tuple
import httpx
from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

GOODREADS_RSS_BASE = "https://www.goodreads.com/review/list_rss/{user_id}"
DEFAULT_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    "Accept": "application/rss+xml, application/xml, text/xml, */*",
}


class GoodreadsBook(BaseModel):
    """Represents a book retrieved from a user's Goodreads shelf."""
    book_id: str = Field(..., description="Goodreads Book ID")
    title: str = Field(..., description="Raw title from Goodreads")
    clean_title: str = Field(..., description="Sanitized title for catalog search")
    author: str = Field(..., description="Author name")
    isbn: Optional[str] = Field(None, description="ISBN 10 or 13")
    cover_image_url: Optional[str] = Field(None, description="Book cover image URL")
    user_rating: Optional[int] = Field(0, description="User rating if rated (1-5)")
    user_shelves: Optional[str] = Field(None, description="Shelves assigned by user")
    date_added: Optional[str] = Field(None, description="Date added to shelf")
    link: Optional[str] = Field(None, description="Link to Goodreads book page")


def extract_goodreads_user_id(input_str: str) -> str:
    """Extracts numeric user ID from a Goodreads profile URL, shelf URL, or raw ID string."""
    if not input_str:
        return ""

    input_str = input_str.strip()

    # If it's already digits, return directly
    if input_str.isdigit():
        return input_str

    # Profile URL: https://www.goodreads.com/user/show/12345678-user-name
    m = re.search(r"/user/show/(\d+)", input_str)
    if m:
        return m.group(1)

    # Shelf URL: https://www.goodreads.com/review/list/12345678 or list_rss/12345678
    m = re.search(r"/review/list(?:_rss)?/(\d+)", input_str)
    if m:
        return m.group(1)

    # Fallback to first continuous sequence of 5+ digits
    m = re.search(r"\b(\d{5,12})\b", input_str)
    if m:
        return m.group(1)

    return input_str


def extract_goodreads_user_name(input_str: str, channel_title: Optional[str] = None) -> Optional[str]:
    """
    Extracts display name of the user from:
    1. Channel title tag e.g. "Javier Bermejo's bookshelf: to-read"
    2. URL slug e.g. "https://www.goodreads.com/user/show/155193797-javier-bermejo"
    """
    # 1. Try RSS channel title
    if channel_title:
        m = re.search(r"^(.*?)(?:'s|’s)\s+bookshelf", channel_title.strip(), re.IGNORECASE)
        if m:
            name = m.group(1).strip()
            if name and not name.isdigit():
                return name

    # 2. Try URL slug
    if input_str:
        m = re.search(r"/user/show/\d+[-_]([a-zA-Z0-9_\-]+)", input_str.strip())
        if m:
            raw_slug = m.group(1)
            # Remove any trailing query params or slashes
            raw_slug = raw_slug.split("?")[0].split("/")[0]
            words = re.split(r"[-_]+", raw_slug)
            cleaned = " ".join(w.capitalize() for w in words if w)
            if cleaned:
                return cleaned

    return None


def clean_book_title_for_search(title: str) -> str:
    """
    Sanitizes book title for search against library OPACs:
    - Removes series tags in parentheses e.g. "(The Lord of the Rings, #1)"
    - Removes edition tags in brackets/parentheses e.g. "[Graphic Novel]", "(Spanish Edition)"
    - Cleans extraneous symbols and extra whitespace
    """
    if not title:
        return ""

    t = title.strip()

    # Remove content in brackets [...]
    t = re.sub(r"\[.*?\]", " ", t)

    # Remove series and edition details in parentheses (...)
    t = re.sub(
        r"\((?:[^)]*#\d+|[^)]*(?:edition|edici[oó]n|series|saga|book|volumen|volume|trilog[íi]a|classics|collection)[^)]*)\)",
        " ",
        t,
        flags=re.IGNORECASE,
    )

    # If parentheses still remain at the end of the title, remove them
    t = re.sub(r"\([^)]*\)\s*$", " ", t)

    # If title has a subtitle with colon or slash and title is long, preserve main title
    if ":" in t:
        parts = t.split(":")
        if len(parts[0].strip()) >= 3:
            t = parts[0].strip()

    # Clean multiple spaces and trailing punctuation
    t = re.sub(r"[^\w\s\-\.\'\,\¿\?\¡\!]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()

    return t


async def fetch_goodreads_shelf(
    user_id_or_url: str,
    shelf: str = "to-read",
    timeout: float = 15.0,
) -> Tuple[List[GoodreadsBook], Optional[str]]:
    """Fetches and parses a public Goodreads user shelf via RSS feed, returning (books, user_name)."""
    user_id = extract_goodreads_user_id(user_id_or_url)
    if not user_id:
        raise ValueError("No se pudo identificar un ID de usuario de Goodreads válido.")

    shelf_name = (shelf or "to-read").strip()
    feed_url = f"https://www.goodreads.com/review/list_rss/{user_id}?shelf={shelf_name}"

    logger.info(f"Fetching Goodreads RSS feed from {feed_url}")

    async with httpx.AsyncClient(headers=DEFAULT_HEADERS, follow_redirects=True, timeout=timeout) as client:
        resp = await client.get(feed_url)
        if resp.status_code == 404:
            raise ValueError(f"Estantería '{shelf_name}' o usuario '{user_id}' no encontrados en Goodreads. Asegúrese de que el perfil sea público.")
        if resp.status_code != 200:
            raise ValueError(f"Error al obtener estantería de Goodreads (Código HTTP {resp.status_code}).")

        xml_content = resp.text

    # Parse RSS XML
    try:
        root = ET.fromstring(xml_content)
    except ET.ParseError as e:
        logger.error(f"Error parsing Goodreads XML feed: {e}")
        raise ValueError(f"Respuesta XML no válida de Goodreads: {str(e)}")

    channel = root.find("channel")
    if channel is None:
        return [], None

    # Extract user name from channel title or URL slug
    channel_title_el = channel.find("title")
    channel_title = channel_title_el.text if channel_title_el is not None else None
    user_name = extract_goodreads_user_name(user_id_or_url, channel_title=channel_title)

    books: List[GoodreadsBook] = []

    for item in channel.findall("item"):
        # Helper to get element text safely
        def get_text(tag: str, default: str = "") -> str:
            el = item.find(tag)
            return el.text.strip() if el is not None and el.text else default

        book_id = get_text("book_id") or get_text("guid")
        raw_title = get_text("title")
        if not raw_title:
            continue

        clean_title = clean_book_title_for_search(raw_title)
        author_name = get_text("author_name")
        isbn = get_text("isbn") or get_text("isbn13")
        cover_img = (
            get_text("book_large_image_url")
            or get_text("book_medium_image_url")
            or get_text("book_image_url")
        )
        if cover_img and "nophoto" in cover_img:
            cover_img = None

        rating_str = get_text("user_rating", "0")
        try:
            user_rating = int(rating_str)
        except ValueError:
            user_rating = 0

        date_added = get_text("user_date_added") or get_text("pubDate")
        link = get_text("link")
        shelves = get_text("user_shelves")

        books.append(
            GoodreadsBook(
                book_id=book_id or f"gr_{len(books)+1}",
                title=raw_title,
                clean_title=clean_title or raw_title,
                author=author_name,
                isbn=isbn if isbn else None,
                cover_image_url=cover_img,
                user_rating=user_rating,
                user_shelves=shelves if shelves else None,
                date_added=date_added,
                link=link if link else None,
            )
        )

    return books, user_name
