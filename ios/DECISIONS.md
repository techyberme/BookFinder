# Decision log — Zahorí iOS

Running log of choices made while porting the Python/web app. Newest at the bottom.
"Python" means `backend/` + `frontend/app.js` at commit `019cc90`.

| # | Decision | Why |
|---|----------|-----|
| 1 | **iOS 17 minimum**, Swift 5.9 tools / Swift 5 language mode, SwiftUI + Observation. | `@Observable` and `String(localized:)` need iOS 17; no dependency forces anything higher. Built and tested with Xcode 26.5. |
| 2 | Core code lives in a **local Swift package `ZahoriKit`** with two libraries: `ZahoriCore` (models, geo, proximity, text rules — Foundation only) and `ZahoriKit` (SwiftSoup/XMLParser parsing, networking, batch, cache). | Everything except UI runs with `swift test` on macOS in seconds, and the proximity logic has no UI or network dependency. |
| 3 | **SwiftSoup** (SPM, `from: 2.7.0`, resolved 2.14.3) for OPAC HTML; **XMLParser** for the Goodreads RSS. | OPAC markup is not well-formed XML; the RSS is. |
| 4 | **Fixtures captured live** on 2026-10-18 with `Scripts/capture_fixtures.sh` (same headers, cookie jar and payloads as `scraper.py`). | The repo had no saved responses; you chose "capture live now". |
| 5 | **Golden tests**: `Scripts/make_golden.py` runs the *Python* functions over every fixture and writes `golden.json`; Swift tests compare field by field. | Proves "reproduce exactly" against the reference instead of against my reading of it. |
| 6 | `libraries.json` is a **verbatim export of `MADRID_LIBRARIES_DB`** by the same script. | No invented coordinates. 64 libraries, same order (lookup order matters for ambiguous names). |
| 7 | BeautifulSoup semantics reproduced in `Soup.swift` (`get_text(" ", strip=True)`, `.string`, class-substring matching, `find_next_sibling`). Python regex/str semantics in `PyText.swift` (`\w`, `isdigit`, `round(x, 2)` via `%.2f`). | Golden tests on real markup pass only with these exact semantics. |
| 8 | **Proximity origin when nothing is selected**: device location, or Madrid center (Puerta del Sol, 40.4168/-3.7038 — the point used in `test_geo.py`) if permission is denied. With ≥1 selected library the behaviour is identical to Python. | Your answer: "fallback origin". |
| 9 | **Recomendaciones stay random** (shuffle → chunks of 3 → `limit_per_book=1` → stop at 2). RNG is injectable; tests use a seeded SplitMix64. | Your answer: "keep random". |
| 10 | **"Catálogo no disponible" is a distinct state** (`SearchOutcome.catalogUnavailable`). Python returns "No encontrado en catálogo" when the OPAC fails. | Explicit requirement in the brief. Tested. |
| 11 | Also treated as *catalog unavailable* (Python returns "0 results"): a search page with none of the known markers; a detail page without a title; every detail page of a result list failing. Some-but-not-all failing → results kept, flagged `isPartial`. | Changed markup must not look like "book not in catalog". |
| 12 | **A fresh in-memory cookie jar per search** (ephemeral `URLSession`), not one jar persisted across launches. | Python creates a new `httpx.AsyncClient` per search; OPAC session tokens live in the URL path and expire in 1 h, so persisting them would only add failures. "Persistent" = across the requests of one session. |
| 13 | **Timeouts: OPAC 20 s, Goodreads 15 s.** | `main.py` builds `AbsysNetScraper(timeout=20.0)`; Goodreads uses 15 s. The brief suggested 15 s; the code wins. |
| 14 | **Retries**: GETs retried once on timeout/transport error/502/503/504 (0.6 s delay). POSTs never retried. | Brief asks for retries; Python has none. Retrying the search POST could double-submit in a stale session. |
| 15 | Form bodies encoded **UTF-8, `+` for spaces** exactly like httpx, although the OPAC serves ISO-8859-1. Responses decoded with the declared charset (Latin-1). | Matches Python byte for byte (test compares against httpx output); live tests confirm the OPAC accepts it. |
| 16 | **Concurrency cap = 3 concurrent book checks** (actor semaphore `ConcurrencyLimiter`), not 3 HTTP requests. Each check's detail pages are fetched concurrently, like `asyncio.gather`. | That is what the Python code does (README says "3 OPAC requests"; code caps book checks). See open question Q3. |
| 17 | **One batch for the whole shelf** with the cap of 3, progress "X de Y" per finished book. | The web sends chunks of 4 sequentially to a server with a semaphore of 3; results are identical, progress is smoother. |
| 18 | **Grouping is recomputed locally** whenever libraries/radius/location change; raw results are stored ungrouped. | The web only re-renders stale server-side groups when settings change (effectively a no-op). Grouping is pure, so doing it right is free. |
| 19 | Batch title is **cleaned twice** (`clean_title` then `clean_book_title_for_search` again). | Reproduces the frontend→backend double cleaning. |
| 20 | **Persistence: Codable JSON files** in Application Support (`settings.json`, `availability-cache.json`). Settings now include selected libraries + radius (web did not persist them). | Brief allows Codable files; no queries needed, so SwiftData adds nothing. |
| 21 | **Cache policy**: found/no-results overwrite the entry; catalog-unavailable shows the last good entry with "actualizado hace X". Shelf also cached and shown with a banner if Goodreads fails. | Brief: offline display with timestamp. |
| 22 | Default radius **5 km** (web slider), not 3 km (API default). | The UI value is what users get in the web app. |
| 23 | Fonts: static TTFs of Fraunces (400/600/700), Plus Jakarta Sans (400–800), JetBrains Mono (400/600) from Google Fonts, OFL licences bundled. Sizes use `relativeTo:` for Dynamic Type. | Static instances register reliably via `UIAppFonts`. |
| 24 | Navigation bar: only fonts are customised (Fraunces large titles); background left to the system. | A custom transparent `UINavigationBarAppearance` made large titles invisible on iOS 26. |
| 25 | Palette: slate neutrals + one accent, Madrid crimson `#C8102E` (`brand-500` in the web Tailwind config); green/amber only as status semantics. | Matches the web's editorial look. |
| 26 | Localisation: three String Catalogs (`es` source). Python's Spanish summaries ("Disponible en X (a 1.4 km)") are catalog keys with interpolation. Command-line builds don't update catalogs, so `Scripts/sync_string_catalogs.py` fills them from the compiler's `.stringsdata`. | English can be added by adding a language in Xcode. |
| 27 | DEBUG-only launch arguments `-ZahoriTab n`, `-ZahoriSearch "title|author"`, `-ZahoriScrollTo sections` for screenshots/manual QA. Compiled out of Release. | Lets screens be verified from the command line. |
| 28 | Book detail shows the **first edition** only (Python's `full_result = results[0]`), while the summary counts every edition. | Reproduces Python. See open question Q5. |
| 29 | Only the 2 recommended books get their status updated after Recomendaciones, as in the web app. | Reproduces `findAvailableRecommendations`. |
| 30 | **Préstamos (reader area)** added after the port, scoped to the loans list + due-date reminders; renewals deliberately left out. | Your choice. Read-only first; renewing changes the account. |
| 31 | Loans parsed from the hidden `varJSONpr` block and element ids/classes only. | The saved pages had accents replaced by `�`; class-based parsing survives that and is less brittle than labels. |
| 32 | Login success = "Desconectar" (ACC=202) link present and no password field; password field shown again = wrong credentials; anything else = catalog unavailable. | No failed-login page was available; this is the most conservative detection. |
| 33 | Credentials in the Keychain, this device only, after-first-unlock; saved only after a successful login. | Your choice ("Keychain"). Prevents storing typos. |
| 34 | Reader session closed with "Desconectar" after every fetch, even on errors. | Polite to the OPAC; avoids leaving an authenticated session open. |
| 35 | Reminders at 10:00 Europe/Madrid, N days before (default 2, 1–7) + due day; past ones skipped; stable ids so rescheduling replaces them. | OPAC dates are Madrid time regardless of where the phone is. |
| 36 | Fixtures anonymised by structure (whole sections removed) plus a guard that fails on e-mail/phone/DNI/old dates; the real loan replaced with a fictional one. | The saved pages still contained personal data and reading history. The script never contains the user's values. |
| 37 | `AppSettings` decodes missing keys with defaults. | Adding reminder settings must not reset existing settings files. |
| 38 | The wrong-password live test needs its own flag (`ZAHORI_TEST_WRONG_PIN=1`). | Failed logins may count towards an account lockout. |
