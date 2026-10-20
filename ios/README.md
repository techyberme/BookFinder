# Zahorí — iOS

Native SwiftUI port of Zahorí: finds which Madrid public library has the books on your Goodreads shelf on the shelf *right now*. The Python/web app in the repository root is the reference implementation; see [MIGRATION.md](MIGRATION.md) for the behaviour map and [DECISIONS.md](DECISIONS.md) for every choice made along the way.

- iOS 17+, iPhone · Swift 5.9 · SwiftUI + Observation · SwiftSoup (SPM)
- Spanish UI (String Catalogs, English-ready) · light & dark mode

## Setup

1. Open `ios/Zahori.xcodeproj` in Xcode 16 or later (built with Xcode 26.5).
2. Target **Zahori** → *Signing & Capabilities* → pick your team. If the bundle id `es.zahori.Zahori` is taken, change it.
3. Choose an iPhone simulator or device and Run. Swift Package dependencies resolve automatically.

In the app: *Estantería* → paste a Goodreads ID or profile URL (or **Cargar cuenta demo**); *Bibliotecas* → pick reference libraries and the radius; *Buscar* → direct catalog search; *Préstamos* → log in with your library card to see your loans and get due-date reminders.

In the simulator, set a location with *Features → Location* (or `xcrun simctl location booted set 40.4153,-3.6845`). With no library selected, distances are measured from your location, or from Madrid center if permission is denied.

## Layout

```
ios/
├── Zahori.xcodeproj           app project (folders are synchronized: new files are picked up automatically)
├── Zahori/                    SwiftUI app: AppModel, LocationProvider, Theme, Views/, Resources/ (fonts, assets, xcstrings)
├── ZahoriKit/                 local Swift package
│   ├── Sources/ZahoriCore/    pure: models, libraries.json, Haversine + proximity, title/ID rules, summaries
│   ├── Sources/ZahoriKit/     OPAC parser + client, Goodreads client/parser, HTTPClient, batch, cache, settings
│   └── Tests/ZahoriKitTests/  XCTest + Fixtures/ (captured pages, golden.json)
├── Zahori.xctestplan          offline tests (default)
├── Live.xctestplan            live network tests (ZAHORI_LIVE_TESTS=1)
└── Scripts/                   fixture capture, golden generation, string-catalog sync
```

## Tests

| What | How |
|---|---|
| Everything offline, fast (macOS, no simulator) | `cd ios/ZahoriKit && swift test` |
| Same suite in Xcode | ⌘U with the **Zahori** test plan, or `xcodebuild -project ios/Zahori.xcodeproj -scheme Zahori -testPlan Zahori -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` |
| Live OPAC + Goodreads (opt-in) | `ZAHORI_LIVE_TESTS=1 swift test --filter LiveTests`, or the **Live** test plan |
| Live reader login with your card (opt-in) | `ZAHORI_LIVE_TESTS=1 ZAHORI_CARNE=… ZAHORI_PIN=… swift test --filter LiveTests/testLiveReaderLoans` — prints only counts and dates |
| Live rejected login (opt-in, may count towards a lockout) | add `ZAHORI_TEST_WRONG_PIN=1` and filter `LiveTests/testLiveReaderWrongPassword` |

75 offline tests: geo/proximity, Goodreads parsing and name extraction, OPAC parsing on real captured pages, the full session/search flow against a mock `URLProtocol`, batch summaries, the 3-check concurrency cap, recommendations, cache, and every "catalog unavailable" path, and the reader area (login form, login/logout flow, loans parsing, wrong password, reminders in Madrid time). Live tests are skipped unless the environment variable is set, so CI stays deterministic.

**Golden tests.** Expected values are not hand-written: `Scripts/make_golden.py` runs the Python backend over the same fixtures and writes `Fixtures/golden.json`. If you change Python behaviour on purpose, regenerate it (from the repo root): `python3 ios/Scripts/make_golden.py`.

## When the OPAC changes

Symptoms: books show **"Catálogo no disponible"** with a reason such as *"El catálogo devolvió una página no reconocida"*, or live tests fail. The app never reports unknown markup as "not found".

1. **Capture fresh pages:** `ios/Scripts/capture_fixtures.sh` (repeats the Python request sequence with curl into `Fixtures/`). Diff against the old ones with `git diff --stat ios/ZahoriKit/Tests/ZahoriKitTests/Fixtures`.
2. **See what breaks:** `cd ios/ZahoriKit && swift test`. `ScraperParsingTests.testClassifiesCapturedPages` tells you which page type is no longer recognised.
3. **Fix the selectors in one place**, `Sources/ZahoriKit/OPACParser.swift`:

   | Concern | Where | Current marker |
   |---|---|---|
   | Session redirect | `sessionRedirect` | `<meta content="0; URL=…">` on `abnetopac?ACC=101` |
   | Search form | `formAction` | `form[name=abnform]` on `?ACC=120&FORM=2` |
   | Page type | `classify` | list: `div.c-docs_info`; empty: "NO recupera resultados" / "no se han encontrado" / "0 docs."; record: `dt` "Título" or `td.copias_tableDisp` |
   | Result list | `parseList` | `a[href*=ACC=165]`, `span.c-docs_author/title/titleRest`, `dl` |
   | Record metadata | `parseDetail` | `dt`/`dd` labels (Título, Autor/Autora, Publicación, Año, ISBN…) |
   | Copies | `parseHoldings`, `loanStatus` | `div.c-accordion_item` → header with "accordion" class → `table tr td×4`, `span.icm_locSign`, `a.js-evn-copiasDetail-indexSign[data-bc]` |
   | Form fields | `OPACClient.payload` | `ACC=131 FORM=2 xsnf12 xsqf12 xsqf03 xsqf01 xsnlis xssort` |

4. Keep the Python scraper in step (it is the reference), then rerun `make_golden.py` and both test suites.
5. New library branch names: add the library or alias to `MADRID_LIBRARIES_DB` in Python and rerun `make_golden.py` — it regenerates `libraries.json`. Don't edit the JSON by hand.

## Préstamos (reader area)

Not part of the Python app. Flow: OPAC session → POST the `abnopid` form (`ACC=201`, `FBC`, `NAC`, `leid` = card, `lepass` = password) → "Mi biblioteca" (`ACC=210`) → parse → "Desconectar" (`ACC=202`). Each loan is read from the hidden `p.varJSONpr` block of `li[id^=lector_box]` inside `#lector_PR` (barcode, title, branch, due date `prfdev`, renewals `prnren`/`ppdrnm`, renewal window `ppdrna`, reservations `xsresv`) — no accented labels are used. Code: `ReaderParser.swift`, `ReaderClient.swift`, `ZahoriCore/Loans.swift`; app: `LoansModel.swift`, `CredentialStore.swift`, `Views/LoansView.swift`.

- **Credentials** live in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synced) and are saved only after a successful login. *Cerrar sesión y olvidar el carné* deletes them, the cached loans and all reminders.
- **Reminders** are local notifications at 10:00 Madrid time, N days before (1–7, default 2) and on the due date. They are rebuilt after every refresh, so a renewal done on the web is picked up the next time the app opens.
- **Fixtures** (`lector_*.html`) are generated by `Scripts/make_reader_fixtures.py` from pages saved in a browser while logged in. It removes personal sections by structure, replaces the real loan with a fictional one, restores accents (browsers often save these Latin-1 pages as UTF-8 with `�`), writes ISO-8859-1, and **refuses to write** if anything resembling an e-mail, phone, DNI or birth date remains. Never commit the raw saved pages.

## Localisation

Source language is Spanish. Xcode keeps the String Catalogs in sync when you build in the IDE; after command-line builds run `python3 ios/Scripts/sync_string_catalogs.py <DerivedData>/Build/Intermediates.noindex`. To add English: project → Info → Localizations → **+**, then translate in the three `Localizable.xcstrings` files. Due dates stay in the OPAC's `DD/MM/YYYY` text.

## Fonts

Fraunces, Plus Jakarta Sans and JetBrains Mono, static TTFs under the SIL Open Font License (licences in `Zahori/Resources/Fonts`), registered via `UIAppFonts` in `Zahori/Info.plist`.

## Debug launch arguments

DEBUG builds only (compiled out of Release): `-ZahoriTab 1` opens a tab (0 shelf, 1 search, 2 libraries), `-ZahoriSearch "Cien años de soledad|García Márquez"` runs a search, `-ZahoriScrollTo sections` scrolls to the first edition's copy groups.

## Open questions and risks

**Q1. Goodreads feed reliability.** The app depends on the undocumented `review/list_rss` feed; Goodreads closed its public API in 2020 and could remove this too. The feed only works for public profiles, returns at most ~100 items per page (the app reads the first page only, like Python), and the demo account currently has a single English book. A CSV import (Goodreads → *Import and export*) would be a robust fallback.

**Q2. App Store review.** Scraping a government catalogue (Comunidad de Madrid, AbsysNet) may hit guideline 5.2 (third-party content/intellectual property) and 4.2 (minimum functionality) if the reviewer sees it as a wrapper. Mitigations: ask the Red de Bibliotecas for written permission (or an official API/Z39.50/SRU endpoint), keep the polite cap of 3 checks, avoid their logo, and state the non-affiliation in the description. Note the Goodreads name/data as well (no Goodreads branding is used).

**Q3. Concurrency cap: README vs code.** The README says "max 3 concurrent OPAC requests"; the code caps 3 concurrent *book checks*, each of which may fetch 2 detail pages at once (up to ~6 simultaneous requests). I followed the code. A stricter global cap of 3 HTTP requests is a one-line change in `HTTPClient` if you prefer it.

**Q4. "Alternativas Cercanas" includes copies on loan.** The README says nearby branches "that hold available copies"; the code (and web UI) lists every copy within the radius, sorted available-first at equal distance. I followed the code.

**Q5. Detail screen shows only the first edition** (Python's `full_result`), while the summary and "Ejemplares (N)" count copies across all checked editions (up to 2). So "Ejemplares (14)" can open a list of 10. Showing all editions is easy if you want it.

**Q6. App Transport Security.** Not an issue: the OPAC (`gestiona.comunidad.madrid`) is HTTPS with HSTS, Goodreads and its covers are HTTPS. No ATS exceptions are configured.

**Q7. Fragility of the scraper.** Session tokens live in the URL path and expire after an hour; markup is undocumented and server-rendered. The app degrades to "Catálogo no disponible" with cached results, but a redesign needs a code update and an app release. Also note *"Ver ficha en OPAC"* links embed a session token and stop working after ~1 h — same as the web app.

**Q8. Things I had to decide without the reference:** Madrid center = Puerta del Sol (40.4168, −3.7038) for the no-permission fallback; "tu ubicación"/"el centro de Madrid" as the distance label; one GET retry; cache keyed by Goodreads `book_id` (if the feed falls back to the review URL as id — a Python quirk kept as-is — the key is that URL); iPhone-only target; bundle id `es.zahori.Zahori`.

**Q9. Location permission.** Requested on first launch only when no library is selected. Review may ask why — the usage string explains it, but you may prefer to request it from the Bibliotecas tab only.

**Q10. Reader login (Préstamos).** Built from pages you saved while logged in; I have not seen a *failed* login, an expired-password page, or an account with reservations, so those paths rely on detection (login form shown again → wrong credentials; anything else unknown → "no se pudieron consultar"). Run `testLiveReaderLoans` once to confirm. The OPAC page also carries a hidden "Tiene préstamos sobrepasados" template that its JavaScript fills in; it is not a real alert and the app ignores it. Storing credentials for a government service raises the App Store review question in Q2 further. Renewing from the app is not implemented.
