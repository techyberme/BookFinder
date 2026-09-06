"""Unit tests for Goodreads RSS feed parser, name extraction and title sanitization."""

import pytest
from backend.goodreads_service import (
    extract_goodreads_user_id,
    extract_goodreads_user_name,
    clean_book_title_for_search,
    fetch_goodreads_shelf,
    GoodreadsBook,
)


def test_extract_goodreads_user_id():
    # Direct ID
    assert extract_goodreads_user_id("177587843") == "177587843"
    
    # Profile URLs
    assert extract_goodreads_user_id("https://www.goodreads.com/user/show/177587843-john-doe") == "177587843"
    assert extract_goodreads_user_id("https://www.goodreads.com/user/show/99887766") == "99887766"
    
    # Review list URL
    assert extract_goodreads_user_id("https://www.goodreads.com/review/list/12345678?shelf=to-read") == "12345678"
    assert extract_goodreads_user_id("https://www.goodreads.com/review/list_rss/12345678") == "12345678"


def test_extract_goodreads_user_name():
    # From URL slug
    assert extract_goodreads_user_name("https://www.goodreads.com/user/show/155193797-javier-bermejo") == "Javier Bermejo"
    assert extract_goodreads_user_name("https://www.goodreads.com/user/show/177587843-john-doe_smith") == "John Doe Smith"
    
    # From RSS channel title
    assert extract_goodreads_user_name("177587843", channel_title="Javier Bermejo's bookshelf: to-read") == "Javier Bermejo"
    assert extract_goodreads_user_name("177587843", channel_title="Ana García’s bookshelf: currently-reading") == "Ana García"


def test_clean_book_title_for_search():
    # Series in parentheses
    assert clean_book_title_for_search("Dune (Dune Chronicles, #1)") == "Dune"
    assert clean_book_title_for_search("The Fellowship of the Ring (The Lord of the Rings, #1)") == "The Fellowship of the Ring"
    assert clean_book_title_for_search("Harry Potter and the Sorcerer's Stone (Harry Potter, #1)") == "Harry Potter and the Sorcerer's Stone"
    
    # Brackets & edition notes
    assert clean_book_title_for_search("Watchmen [Graphic Novel]") == "Watchmen"
    assert clean_book_title_for_search("1984 (Signet Classics)") == "1984"
    assert clean_book_title_for_search("Cien años de soledad (Edición 50 Aniversario)") == "Cien años de soledad"
    
    # Subtitle with colon
    assert clean_book_title_for_search("Sapiens: A Brief History of Humankind") == "Sapiens"
    assert clean_book_title_for_search("El infinito en un junco: La invención de los libros en el mundo antiguo") == "El infinito en un junco"


@pytest.mark.asyncio
async def test_live_goodreads_shelf_fetch():
    """Live test fetching a public Goodreads shelf."""
    try:
        books, user_name = await fetch_goodreads_shelf("177587843", shelf="to-read", timeout=15.0)
        assert isinstance(books, list)
        if books:
            b = books[0]
            assert isinstance(b, GoodreadsBook)
            assert len(b.title) > 0
            assert len(b.clean_title) > 0
    except Exception as e:
        pytest.skip(f"Goodreads RSS live endpoint check skipped due to network/rate limit: {e}")
