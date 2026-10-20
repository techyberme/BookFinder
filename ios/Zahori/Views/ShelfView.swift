import SwiftUI
import ZahoriCore

/// Screen 1: shelf with the Recomendaciones hero banner and the book list.
struct ShelfView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var onlyAvailable = false
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            Group {
                if !model.hasProfile {
                    OnboardingView()
                } else {
                    content
                }
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Estantería")
            .toolbar {
                if model.hasProfile {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showProfile = true } label: { ProfileBadge() }
                            .accessibilityLabel(Text("Configurar perfil de Goodreads"))
                    }
                }
            }
            .sheet(isPresented: $showProfile) { ProfileSheet() }
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
        }
    }

    private var filteredBooks: [Book] {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return model.books.filter { book in
            let text = f.isEmpty || book.title.lowercased().contains(f) || book.author.lowercased().contains(f)
            return text && (!onlyAvailable || model.availability(for: book)?.isAvailable == true)
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let error = model.shelfError {
                    ErrorBanner(message: error, cachedAt: model.shelfCachedAt)
                }
                if model.isLoadingShelf && model.books.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in SkeletonCard() }
                }
                if !model.books.isEmpty {
                    RecommendationsBanner()
                    header
                    ForEach(filteredBooks) { book in
                        if model.checks[book.bookID]?.phase == .checking && model.isCheckingBatch {
                            SkeletonCard()
                        } else {
                            BookCard(book: book)
                        }
                    }
                    if filteredBooks.isEmpty {
                        Text("No hay libros que coincidan con los filtros actuales.")
                            .font(Typo.sans(13)).foregroundStyle(Palette.inkSecondary)
                            .frame(maxWidth: .infinity).padding(24).cardStyle()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await model.reloadShelf() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                (model.books.count == 1 ? Text("1 libro en '\(model.settings.shelf)'") : Text("\(model.books.count) libros en '\(model.settings.shelf)'"))
                Text("•")
                Text("\(model.availableCount) disponibles en Madrid").foregroundStyle(Palette.available)
            }
            .font(Typo.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)

            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Palette.inkTertiary)
                    TextField("Filtrar libros...", text: $filter).font(Typo.sans(14))
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.rule))

                Toggle(isOn: $onlyAvailable) { Text("Solo disponibles").font(Typo.sans(12, .semibold)) }
                    .toggleStyle(.button).tint(Palette.available).frame(minHeight: 44)
            }

            Button {
                Task { await model.checkAll() }
            } label: {
                HStack {
                    if model.isCheckingBatch { ProgressView().tint(Palette.paper) }
                    (model.isCheckingBatch ? Text("Comprobando catálogo...") : Text("Comprobar todos en catálogo"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isCheckingBatch)

            if model.isCheckingBatch || (model.batchTotal > 0 && model.batchCompleted < model.batchTotal) {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(model.batchCompleted), total: Double(max(model.batchTotal, 1)))
                        .tint(Palette.accent)
                    Text("\(model.batchCompleted) de \(model.batchTotal)")
                        .font(Typo.mono(12, .semibold)).foregroundStyle(Palette.inkSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Book card

struct BookCard: View {
    @Environment(AppModel.self) private var model
    let book: Book

    var body: some View {
        let check = model.checks[book.bookID]
        let availability = model.availability(for: book)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Cover(url: book.coverImageURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(Typo.serif(17)).foregroundStyle(Palette.ink).lineLimit(3)
                    Text(book.author.isEmpty ? String(localized: "Autor no especificado") : book.author)
                        .font(Typo.sans(13, .medium)).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                    if let isbn = book.isbn {
                        Text("ISBN: \(isbn)").font(Typo.mono(11)).foregroundStyle(Palette.inkTertiary)
                    }
                    if let cachedAt = check?.cachedAt { UpdatedAgoLabel(date: cachedAt).padding(.top, 2) }
                }
            }
            Divider().overlay(Palette.rule)
            HStack(spacing: 8) {
                StatusPill(check: check, availability: availability)
                Spacer(minLength: 4)
                if let a = availability, a.firstEdition?.copies.isEmpty == false {
                    NavigationLink(value: book) {
                        Text("Ejemplares (\(a.totalCopies))")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button {
                    Task { await model.check(book) }
                } label: {
                    Text(check?.phase == .checked ? "Recomprobar" : "Comprobar")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(check?.phase == .checking)
            }
        }
        .padding(14)
        .cardStyle()
    }
}

// MARK: - Errors

struct ErrorBanner: View {
    let message: String
    var cachedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Typo.sans(13, .medium)).foregroundStyle(Palette.accent)
            if let cachedAt {
                Text("Mostrando la última copia guardada.").font(Typo.sans(12)).foregroundStyle(Palette.inkSecondary)
                UpdatedAgoLabel(date: cachedAt)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accentBg, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Profile

struct ProfileBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Text(initials).font(Typo.sans(12, .heavy)).foregroundStyle(Palette.paper)
                .frame(width: 32, height: 32).background(Palette.accent, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(model.settings.goodreadsUserName ?? String(localized: "Mi Perfil")).font(Typo.sans(12, .bold))
                Text(model.settings.shelf).font(Typo.mono(10)).foregroundStyle(Palette.inkSecondary)
            }
            .foregroundStyle(Palette.ink)
        }
        .frame(minHeight: 44)
    }

    /// Port of `getInitials` in frontend/app.js.
    private var initials: String {
        guard let name = model.settings.goodreadsUserName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return "GR" }
        let parts = name.split(whereSeparator: \.isWhitespace)
        if parts.count >= 2 { return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased() }
        if parts.count == 1, parts[0].count >= 2, !parts[0].allSatisfy({ $0.isASCII && $0.isNumber }) {
            return String(parts[0].prefix(2)).uppercased()
        }
        return "GR"
    }
}
