import SwiftUI
import ZahoriCore

/// "Recomendaciones" hero banner: up to 2 shelf books with a copy available right now.
struct RecommendationsBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recomendaciones").eyebrow().foregroundStyle(Palette.accent)
                    Text("Disponibles hoy").font(Typo.serif(24)).foregroundStyle(Palette.ink)
                    Text("Libros de tu lista con disponibilidad inmediata para recoger hoy.")
                        .font(Typo.sans(13)).foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                Button {
                    Task { await model.findRecommendations() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(Palette.ink)
                .disabled(model.isFindingRecommendations)
                .accessibilityLabel(Text("Nuevas sugerencias"))
            }

            if model.isFindingRecommendations {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Buscando libros con disponibilidad inmediata en Madrid...")
                        .font(Typo.sans(12)).foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: 44)
            } else if model.recommendedBooks.isEmpty && model.recommendationsSearched {
                Text("No se encontraron recomendaciones con ejemplares disponibles inmediatamente entre las muestras analizadas. Pruebe a pulsar \"Nuevas sugerencias\".")
                    .font(Typo.sans(12)).italic().foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(model.recommendedBooks) { book in
                    NavigationLink(value: book) { RecommendationCard(book: book) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Palette.accentBg, Palette.card], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.accent.opacity(0.25)))
    }
}

private struct RecommendationCard: View {
    @Environment(AppModel.self) private var model
    let book: Book

    var body: some View {
        let a = model.availability(for: book)
        HStack(alignment: .top, spacing: 14) {
            Cover(url: book.coverImageURL, width: 76)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(Palette.available).frame(width: 7, height: 7)
                    Text("Disponible ahora").eyebrow().foregroundStyle(Palette.available)
                }
                Text(book.title).font(Typo.serif(18)).foregroundStyle(Palette.ink).lineLimit(2)
                Text(book.author.isEmpty ? String(localized: "Autor no especificado") : book.author)
                    .font(Typo.sans(13, .medium)).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(Palette.accent)
                    Text(a?.bestMatchLibrary ?? String(localized: "Biblioteca de la red")).lineLimit(1)
                    if let d = a?.bestMatchDistanceKm, d > 0 {
                        Text("(\(String(format: "%.1f", d)) km)").font(Typo.mono(11)).foregroundStyle(Palette.inkTertiary)
                    }
                }
                .font(Typo.sans(12, .semibold)).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Palette.inkTertiary).padding(.top, 4)
        }
        .padding(12)
        .cardStyle()
        .contentShape(Rectangle())
        .accessibilityHint(Text("Ver ejemplares"))
    }
}
