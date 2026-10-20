import Foundation
import Observation
import ZahoriCore
import ZahoriKit

/// Status of one shelf book. Mirrors the web app's "pending" / "checking" / "checked".
struct BookCheck: Equatable {
    enum Phase: Equatable { case pending, checking, checked }
    var phase: Phase = .pending
    var result: SearchResult?
    /// Set when `result` comes from the cache because the catalog could not be reached.
    var cachedAt: Date?
}

@MainActor @Observable
final class AppModel {
    // MARK: Dependencies
    let directory = LibraryDirectory.shared
    let location = LocationProvider()
    private let goodreads = GoodreadsClient()
    private let service = AvailabilityService(catalog: OPACClient())
    private let cache = AvailabilityCache(url: AvailabilityCache.defaultURL())
    private let settingsStore = JSONFileStore<AppSettings>(filename: "settings.json")

    // MARK: Settings (persisted on every change)
    var settings: AppSettings {
        didSet { if settings != oldValue { try? settingsStore.save(settings) } }
    }

    // MARK: Shelf
    var books: [Book] = []
    var checks: [String: BookCheck] = [:]
    var isLoadingShelf = false
    var shelfError: String?
    /// Non-nil when the shelf on screen is the cached copy (Goodreads unreachable).
    var shelfCachedAt: Date?

    // MARK: Batch
    var isCheckingBatch = false
    var batchCompleted = 0
    var batchTotal = 0

    // MARK: Recomendaciones
    var recommendationIDs: [String] = []
    var isFindingRecommendations = false
    var recommendationsSearched = false

    // MARK: Direct search
    var searchResult: SearchResult?
    var isSearching = false

    init() {
        settings = settingsStore.load() ?? AppSettings()
    }

    // MARK: - Proximity

    var proximity: Proximity {
        Proximity(directory: directory, selectedLibraries: settings.selectedLibraryIDs,
                  radiusKm: Double(settings.radiusKm),
                  fallbackOrigin: settings.selectedLibraryIDs.isEmpty ? location.origin : nil)
    }

    var selectedLibraries: [Library] {
        settings.selectedLibraryIDs.compactMap(directory.library(id:))
    }

    func availability(for book: Book) -> Availability? {
        checks[book.bookID]?.result.map { Availability.summarize($0, proximity: proximity) }
    }

    var availableCount: Int {
        books.filter { availability(for: $0)?.isAvailable == true }.count
    }

    var hasProfile: Bool { settings.goodreadsUserID != nil }

    // MARK: - Goodreads

    /// Port of the profile modal submit handler in frontend/app.js.
    func connect(userInput raw: String, shelf rawShelf: String) async {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let shelf = rawShelf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "to-read" : rawShelf.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            shelfError = String(localized: "Por favor, introduzca su ID de usuario o enlace de perfil de Goodreads.")
            return
        }
        let userID = GoodreadsText.userID(from: input)
        guard !userID.isEmpty else {
            shelfError = String(localized: "No se pudo extraer un ID de usuario de Goodreads válido.")
            return
        }
        settings.goodreadsUserID = userID
        settings.goodreadsUserName = GoodreadsText.userName(from: input) ?? settings.goodreadsUserName
        settings.shelf = shelf
        await loadShelf(userInput: input)
    }

    func disconnect() async {
        settings.goodreadsUserID = nil
        settings.goodreadsUserName = nil
        settings.shelf = "to-read"
        books = []
        checks = [:]
        recommendationIDs = []
        recommendationsSearched = false
        shelfError = nil
        shelfCachedAt = nil
        await cache.clear()
    }

    func reloadShelf() async {
        guard let id = settings.goodreadsUserID else { return }
        await loadShelf(userInput: id)
    }

    /// Shows the cached shelf immediately on launch, then refreshes from Goodreads.
    func restore() async {
        guard let userID = settings.goodreadsUserID else { return }
        if let cached = await cache.shelf(), cached.userID == userID, cached.shelf == settings.shelf {
            books = cached.books
            await applyCachedChecks()
        }
        await loadShelf(userInput: userID)
    }

    private func loadShelf(userInput: String) async {
        isLoadingShelf = true
        shelfError = nil
        defer { isLoadingShelf = false }
        do {
            let result = try await goodreads.fetchShelf(userInput: userInput, shelf: settings.shelf)
            if let name = result.userName ?? GoodreadsText.userName(from: userInput) {
                settings.goodreadsUserName = name
            }
            shelfCachedAt = nil
            let previous = checks
            books = result.books
            checks = previous.filter { id, _ in result.books.contains { $0.bookID == id } }
            await applyCachedChecks()
            await cache.saveShelf(.init(userID: result.userID, shelf: result.shelf, userName: settings.goodreadsUserName,
                                        books: result.books, fetchedAt: Date()))
            if books.isEmpty {
                shelfError = String(localized: "No se encontraron libros en la estantería '\(settings.shelf)'. Verifique que sea pública y contenga libros.")
            } else {
                await findRecommendations()
            }
        } catch {
            if let cached = await cache.shelf(), cached.userID == settings.goodreadsUserID, cached.shelf == settings.shelf {
                books = cached.books
                shelfCachedAt = cached.fetchedAt
                await applyCachedChecks()
            }
            shelfError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Fills unchecked books with their last good result, labelled with its timestamp.
    private func applyCachedChecks() async {
        let entries = await cache.allEntries()
        for book in books where checks[book.bookID]?.phase != .checked {
            if let entry = entries[book.bookID] {
                checks[book.bookID] = BookCheck(phase: .checked, result: entry.result, cachedAt: entry.checkedAt)
            }
        }
    }

    // MARK: - Availability checks

    func check(_ book: Book) async {
        checks[book.bookID, default: BookCheck()].phase = .checking
        let result = await service.check(book, limitPerBook: 2)
        await store(result, for: book)
    }

    func checkAll() async {
        guard !isCheckingBatch, !books.isEmpty else { return }
        isCheckingBatch = true
        batchCompleted = 0
        batchTotal = books.count
        for book in books { checks[book.bookID, default: BookCheck()].phase = .checking }

        await service.checkAll(books, limitPerBook: 2) { [weak self] book, result in
            await self?.store(result, for: book)
            await self?.incrementBatch()
        }
        isCheckingBatch = false
    }

    private func incrementBatch() { batchCompleted += 1 }

    private func store(_ result: SearchResult, for book: Book) async {
        let shown = await cache.record(result, for: book.bookID)
        checks[book.bookID] = BookCheck(phase: .checked, result: shown.result, cachedAt: shown.cachedAt)
    }

    // MARK: - Recomendaciones

    func findRecommendations() async {
        guard !isFindingRecommendations, !books.isEmpty else { return }
        isFindingRecommendations = true
        defer {
            isFindingRecommendations = false
            recommendationsSearched = true
        }
        var rng = SystemRandomNumberGenerator()
        let found = await service.recommendations(from: books, proximity: proximity, targetCount: 2, using: &rng)
        // As in the web app, only the recommended books get their status updated.
        for (book, result) in found {
            await store(result, for: book)
        }
        recommendationIDs = found.map(\.book.bookID)
    }

    var recommendedBooks: [Book] {
        recommendationIDs.compactMap { id in books.first { $0.bookID == id } }
    }

    // MARK: - Direct search

    func search(title: String, author: String) async {
        isSearching = true
        defer { isSearching = false }
        searchResult = await OPACClient().search(title: title, author: author, maxItems: 5)
    }

    // MARK: - Libraries

    func toggleLibrary(_ id: String) {
        if let i = settings.selectedLibraryIDs.firstIndex(of: id) {
            settings.selectedLibraryIDs.remove(at: i)
        } else {
            settings.selectedLibraryIDs.append(id)
        }
    }
}
