import Foundation
import ZahoriCore

/// Async counting semaphore. Python: `asyncio.Semaphore(3)`.
public actor ConcurrencyLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    public func run<T: Sendable>(_ work: @Sendable () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await work()
    }

    private func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            // Hand the slot straight to the next waiter; `running` stays the same.
            waiters.removeFirst().resume()
        }
    }
}

/// Batch and recommendation checks. Port of `check_batch_availability` and
/// `get_shelf_recommendations` (backend/main.py).
public struct AvailabilityService: Sendable {
    /// Python: `asyncio.Semaphore(3)` around each book check.
    public static let maxConcurrentChecks = 3

    public var catalog: CatalogSearching

    public init(catalog: CatalogSearching) {
        self.catalog = catalog
    }

    /// One book. Python sends `clean_title` as `title` and the server cleans it again; same here.
    public func check(_ book: Book, limitPerBook: Int = 2) async -> SearchResult {
        await catalog.search(title: GoodreadsText.cleanTitleForSearch(book.cleanTitle), author: book.author,
                             maxItems: limitPerBook)
    }

    /// Checks every book with at most `maxConcurrentChecks` in flight. Results arrive in completion order;
    /// `onResult` is called once per book (drives the "X de Y" progress).
    public func checkAll(_ books: [Book], limitPerBook: Int = 2,
                         onResult: @escaping @Sendable (Book, SearchResult) async -> Void) async {
        let limiter = ConcurrencyLimiter(limit: Self.maxConcurrentChecks)
        await withTaskGroup(of: Void.self) { group in
            for book in books {
                group.addTask {
                    let result = await limiter.run { await check(book, limitPerBook: limitPerBook) }
                    await onResult(book, result)
                }
            }
        }
    }

    /// Recomendaciones: shuffle the shelf, check 3 at a time (`limit_per_book=1`) and stop once
    /// `targetCount` books are available right now.
    public func recommendations<R: RandomNumberGenerator>(
        from books: [Book], proximity: Proximity, targetCount: Int = 2, using rng: inout R
    ) async -> [(book: Book, result: SearchResult)] {
        var candidates = books
        candidates.shuffle(using: &rng)
        var found: [(book: Book, result: SearchResult)] = []
        let batchSize = 3

        for start in stride(from: 0, to: candidates.count, by: batchSize) where found.count < targetCount {
            let chunk = Array(candidates[start..<min(start + batchSize, candidates.count)])
            let results = await withTaskGroup(of: (Int, SearchResult).self) { group in
                for (i, book) in chunk.enumerated() {
                    group.addTask { (i, await check(book, limitPerBook: 1)) }
                }
                var out = [SearchResult?](repeating: nil, count: chunk.count)
                for await (i, r) in group { out[i] = r }
                return out.map { $0! }
            }
            for (book, result) in zip(chunk, results)
            where Availability.summarize(result, proximity: proximity).isAvailable {
                found.append((book, result))
                if found.count >= targetCount { break }
            }
        }
        return Array(found.prefix(targetCount))
    }
}
