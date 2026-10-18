import SwiftUI
import ZahoriCore

/// Screen 2: availability by library for one shelf book (the web "Detalle de Ejemplares en Red" modal).
struct BookDetailView: View {
    @Environment(AppModel.self) private var model
    let book: Book

    var body: some View {
        let check = model.checks[book.bookID]
        let availability = model.availability(for: book)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    Cover(url: book.coverImageURL, width: 88)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(availability?.firstEdition?.title ?? book.title)
                            .font(Typo.serif(22)).foregroundStyle(Palette.ink)
                        Text(availability?.firstEdition?.author ?? book.author)
                            .font(Typo.sans(14, .medium)).foregroundStyle(Palette.inkSecondary)
                        StatusPill(check: check, availability: availability)
                        if let cachedAt = check?.cachedAt { UpdatedAgoLabel(date: cachedAt) }
                    }
                }

                if let edition = availability?.firstEdition {
                    EditionMeta(edition: edition)
                    if availability?.isPartial == true {
                        Label("Algunas ediciones no se pudieron cargar del catálogo.", systemImage: "exclamationmark.triangle")
                            .font(Typo.sans(12)).foregroundStyle(Palette.onLoan)
                    }
                    GroupedCopiesView(copies: edition.copies, proximity: model.proximity)
                        .padding(14).cardStyle()
                } else if case let .catalogUnavailable(reason)? = check?.result?.outcome {
                    CatalogUnavailableView(reason: reason) { Task { await model.check(book) } }
                } else if check?.phase == .checking {
                    SkeletonCard()
                } else {
                    Button("Comprobar") { Task { await model.check(book) } }.buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(16)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("Ejemplares")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.check(book) } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel(Text("Recomprobar"))
                    .disabled(check?.phase == .checking)
            }
        }
    }
}

struct EditionMeta: View {
    let edition: Edition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let year = edition.year, !year.isEmpty {
                meta("Año", Text(year).font(Typo.mono(12)))
            }
            if let pub = edition.publication, !pub.isEmpty { meta("Publicación", Text(pub)) }
            if let ed = edition.edition, !ed.isEmpty { meta("Edición", Text(ed)) }
            if let isbn = edition.isbn, !isbn.isEmpty { meta("ISBN", Text(isbn).font(Typo.mono(12))) }
            if let s = edition.detailURL, let url = URL(string: s), url.scheme?.hasPrefix("http") == true {
                Link(destination: url) {
                    Label("Ver ficha en OPAC", systemImage: "arrow.up.right.square")
                        .font(Typo.sans(13, .semibold)).frame(minHeight: 44)
                }
                .tint(Palette.accent)
            }
        }
        .font(Typo.sans(12))
        .foregroundStyle(Palette.inkSecondary)
    }

    private func meta(_ label: LocalizedStringKey, _ value: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(Typo.sans(12, .bold)).foregroundStyle(Palette.ink)
            value
        }
    }
}

struct CatalogUnavailableView: View {
    let reason: String
    var retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Catálogo no disponible", systemImage: "exclamationmark.icloud")
                .font(Typo.serif(18)).foregroundStyle(Palette.accent)
            Text("No hemos podido consultar el catálogo de la Red de Bibliotecas. Esto no significa que el libro no exista.")
                .font(Typo.sans(13)).foregroundStyle(Palette.ink)
            Text(reason).font(Typo.mono(11)).foregroundStyle(Palette.inkTertiary)
            Button("Reintentar", action: retry).buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accentBg, in: RoundedRectangle(cornerRadius: 14))
    }
}
