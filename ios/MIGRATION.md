# Migration map — Python/web → Swift

Every behaviour of the reference app and where it lives now. ✅ identical (golden-tested where noted) · 🔁 deliberately changed · ➖ not applicable on iOS.

## Goodreads (`backend/goodreads_service.py`)

| Python | Swift | |
|---|---|---|
| `extract_goodreads_user_id` | `GoodreadsText.userID(from:)` | ✅ golden |
| `extract_goodreads_user_name` (channel title, then URL slug) | `GoodreadsText.userName(from:channelTitle:)` | ✅ golden |
| `clean_book_title_for_search` | `GoodreadsText.cleanTitleForSearch` | ✅ golden (21 titles) |
| RSS fetch `list_rss/{id}?shelf=`; 404 / non-200 / bad XML messages | `GoodreadsClient.fetchShelf` + `FetchError` (same Spanish texts) | ✅ |
| RSS parse (`book_id`→`guid`→`gr_N`, cover large→medium→small, `nophoto`→nil, rating int or 0, …) | `GoodreadsRSSParser` | ✅ golden (live + synthetic feed) |
| `GoodreadsBook` | `Book` | ✅ |

## OPAC scraper (`backend/scraper.py`)

| Python | Swift | |
|---|---|---|
| `_init_session`: ACC=101 → meta refresh → session home → `?ACC=120&FORM=2` → `form[name=abnform]` action | `OPACClient.openSession` + `OPACParser.sessionRedirect/formAction` | ✅ fixture + live |
| Cookie jar per `httpx.AsyncClient` | Ephemeral `URLSession` per search (`HTTPClient`) | ✅ |
| Payloads (ACC=131, FORM=2, `xsnf12` 0/4, `xsqf03`, `xsnlis`, `xssort`) and query cleaning (`J.K.`→`J K`) | `OPACClient.payload`, `cleanQuery` | ✅ body byte-identical to httpx |
| Author-only keyword fallback (`xsqf01`) | `OPACClient.runSearch` | ✅ |
| No-results detection | `OPACParser.classify → .noResults` | ✅ |
| Single record → detail page | `.singleRecord` | ✅ |
| List page (`c-docs_info`, `ACC=165` link, title + titleRest, `dl` publication) | `OPACParser.parseList` | ✅ golden (3 pages) |
| Detail fetches in parallel, placeholder on failure | `OPACClient.fetchDetails` | ✅ (+ partial flag) |
| `_parse_detail_page` (dt/dd metadata, title fallback, year from publication) | `OPACParser.parseDetail` | ✅ golden |
| `_parse_holdings_from_html` (branch, room, signatura, barcode, type, support, Disponible/Prestado, DD/MM/YYYY) | `OPACParser.parseHoldings`, `loanStatus` | ✅ golden (10 live copies + sample) |
| Unknown markup / no title / all detail pages fail → empty success | `.catalogUnavailable` | 🔁 brief requirement |
| `HoldingItem`, `BookResult`, `SearchResponse` | `Copy`, `Edition`, `SearchResult` (`SearchOutcome` enum instead of `success/error`) | ✅ / 🔁 shape |
| Timeout 20 s (main.py) | `OPACClient(timeout: 20)` | ✅ |
| No retries | One GET retry on transient failures | 🔁 brief requirement |

## Geo (`backend/madrid_libraries_geo.py`)

| Python | Swift | |
|---|---|---|
| `MADRID_LIBRARIES_DB` (64 libraries) | `ZahoriCore/Resources/libraries.json` (generated) | ✅ verbatim |
| `normalize_text` | `LibraryDirectory.normalize` | ✅ golden |
| `find_library_geo` (exact alias → substring → ≥2 tokens) | `LibraryDirectory.find` | ✅ golden (83 names) |
| `haversine_distance` (rounded to 2 dp) | `Geo.haversineKm` | ✅ golden (129 pairs) |
| `get_all_libraries_list` order | `LibraryDirectory.sortedList` | ✅ golden |
| `_apply_geospatial_grouping` | `Proximity.group` | ✅ golden (7 selections) |
| — (no geolocation) | `fallbackOrigin`: device location / Madrid center when nothing selected | 🔁 your decision |

## API endpoints (`backend/main.py`) → in-process services

| Endpoint | Swift | |
|---|---|---|
| `GET /api/libraries` | `LibraryDirectory.shared` | ✅ |
| `GET /api/search` (limit 5 from UI) | `AppModel.search` → `OPACClient.search(maxItems: 5)` | ✅ |
| `GET /api/goodreads/shelf` | `GoodreadsClient` | ✅ |
| `POST /api/check-batch-availability` (semaphore 3, `limit_per_book` 2) | `AvailabilityService.checkAll` / `check` | ✅ cap tested |
| Summary rules (`Disponible en X`, `Prestado en X`, `(a N.N km)`, `Prestado (N ejemplares en red)`, …) | `Availability.summarize` | ✅ golden (8 cases) |
| Exception / failed search → "No encontrado en catálogo" or "Error: …" | `.catalogUnavailable` → "Catálogo no disponible" | 🔁 |
| `POST /api/goodreads/recommendations` (shuffle, chunks of 3, limit 1, target 2) | `AvailabilityService.recommendations` | ✅ (random order not reproducible across languages) |
| `max_length=50/100` request validation | — | ➖ no HTTP boundary; a shelf > 100 books no longer breaks Recomendaciones |
| `/api/health`, PWA manifest, service worker, static files, Docker/Procfile | — | ➖ |

## Frontend (`frontend/app.js`)

| Web | iOS | |
|---|---|---|
| Profile modal (ID/URL + shelf, demo `177587843`, disconnect) | `OnboardingView` / `ProfileSheet` | ✅ |
| `localStorage` user id / name / shelf | `settings.json` | ✅ (+ libraries, radius) |
| Header initials (`getInitials`) | `ProfileBadge` | ✅ |
| Recomendaciones hero, "Nuevas sugerencias", auto-run after load | `RecommendationsBanner` | ✅ |
| Shelf filter + "Solo disponibles" | `ShelfView` | ✅ |
| Per-book Comprobar/Recomprobar, "Ejemplares (N)" | `BookCard` | ✅ |
| Check all: chunks of 4, progress `X / Y` | one capped batch, "X de Y", skeleton cards | 🔁 smoother, same results |
| Holdings modal (first edition, three groups) | `BookDetailView` + `GroupedCopiesView` | ✅ |
| Direct search, quick-fill examples, branch filter, only-available, edition cards, "Ver ficha en OPAC" | `SearchView` | ✅ |
| Library multi-select dropdown (name/district/municipality, max 15 shown) | `LibrarySettingsView` searchable list (all matches shown) | 🔁 |
| Radius slider ⇄ number input, clamp 1–20 on blur, default 5 | Slider ⇄ TextField, same clamp | ✅ |
| Changing settings re-renders stale groups | Regroups live | 🔁 |
| Service-worker offline shell | Cached shelf + results with "actualizado hace X" | 🔁 |

## New in iOS (no Python equivalent)

| Feature | Swift |
|---|---|
| Reader login (`abnopid`, ACC=201) and logout (ACC=202) | `ReaderClient`, `ReaderParser.loginForm/isLoggedIn` |
| Current loans from "Mi biblioteca" (ACC=210) | `ReaderParser.parseLoans` → `Loan` |
| Due-date reminders | `LoanReminders.plan` (pure, tested) + `LoansModel.scheduleReminders` |
| Credentials | `CredentialStore` (Keychain) |

## Tests (`tests/`)

| Python test | XCTest |
|---|---|
| `test_geo.py` (4) | `GeoTests` (10) |
| `test_goodreads.py` (3 + 1 live) | `GoodreadsTests` (7) + `LiveTests.testLiveGoodreadsShelf` |
| `test_scraper.py` (2 + 3 live) | `ScraperParsingTests` (8) + `NetworkFlowTests` (19) + 3 `LiveTests` |
| `test_api.py` batch / recommendations / geo-filter search (live) | `BatchTests` (13, offline with fakes) + 2 `LiveTests` |
| `test_api.py` health, manifest, service worker, 400 on empty query | ➖ / `testEmptyQueryIsInvalid` |

## Could not replicate exactly

1. **Random order of Recomendaciones** — Swift's shuffle differs from CPython's Mersenne Twister; only the algorithm is identical.
2. **HTML tree differences** — SwiftSoup builds an HTML5 tree (adds `tbody`, repairs nesting) where `html.parser` does not. Identical on every captured page; could diverge on badly broken markup.
3. **Python `\w` / `\s` edge cases** — reimplemented via Unicode categories; combining marks and `\x1c`–`\x1f` behave slightly differently. No effect on real titles.
