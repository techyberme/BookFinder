import SwiftUI
import ZahoriCore

// MARK: - Status pill

struct StatusPill: View {
    let check: BookCheck?
    let availability: Availability?

    var body: some View {
        HStack(spacing: 6) {
            switch (check?.phase, availability?.state) {
            case (.checking?, _):
                ProgressView().controlSize(.mini)
                Text("Comprobando…")
            case (.checked?, .available?):
                Circle().fill(Palette.available).frame(width: 6, height: 6)
                Text(availability!.statusSummary).lineLimit(1)
            case (.checked?, .onLoan?):
                Circle().fill(Palette.onLoan).frame(width: 6, height: 6)
                Text(availability!.statusSummary).lineLimit(1)
            case (.checked?, .catalogUnavailable?):
                Image(systemName: "exclamationmark.icloud")
                Text("Catálogo no disponible")
            case (.checked?, .notInCatalog?):
                Text("No en catálogo")
            default:
                Text("Sin comprobar")
            }
        }
        .font(Typo.sans(11, .semibold, relativeTo: .caption))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        guard check?.phase == .checked else { return Palette.inkSecondary }
        switch availability?.state {
        case .available?: return Palette.available
        case .onLoan?: return Palette.onLoan
        case .catalogUnavailable?: return Palette.accent
        default: return Palette.inkTertiary
        }
    }

    private var background: Color {
        guard check?.phase == .checked else { return Palette.chip }
        switch availability?.state {
        case .available?: return Palette.availableBg
        case .onLoan?: return Palette.onLoanBg
        case .catalogUnavailable?: return Palette.accentBg
        default: return Palette.chip
        }
    }
}

// MARK: - Cover

struct Cover: View {
    let url: String?
    var width: CGFloat = 64

    var body: some View {
        Group {
            if let url, !url.isEmpty, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: width * 1.42)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.rule))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Palette.chip
            Text("Sin portada").font(Typo.sans(9, .medium)).foregroundStyle(Palette.inkTertiary)
                .multilineTextAlignment(.center).padding(4)
        }
    }
}

// MARK: - Copy row

struct CopyRow: View {
    let copy: Copy
    var showDistance: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(copy.library).font(Typo.sans(14, .bold)).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                badge
            }
            if showDistance, let d = copy.distanceKm {
                Text(distanceLabel(d))
                    .font(Typo.mono(11, .semibold)).foregroundStyle(Palette.inkSecondary)
            }
            Text("\(copy.location) • \(copy.support) • \(copy.itemType)")
                .font(Typo.sans(12)).foregroundStyle(Palette.inkSecondary)
            HStack(spacing: 6) {
                Text(copy.shelfmark)
                    .font(Typo.mono(12, .semibold)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Palette.chip, in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel(Text("Signatura \(copy.shelfmark)"))
                if let due = copy.dueDate {
                    Label(due, systemImage: "calendar").font(Typo.mono(11)).foregroundStyle(Palette.onLoan)
                        .accessibilityLabel(Text("Devolución prevista \(due)"))
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "📍 1.4 km de Eugenio Trías" — same text as the web holdings table.
    private func distanceLabel(_ d: Double) -> String {
        let km = String(format: "%.1f", d)
        if let ref = copy.relativeToLibrary { return String(localized: "📍 \(km) km de \(ref)") }
        return "📍 \(km) km"
    }

    @ViewBuilder private var badge: some View {
        let text = copy.isAvailable ? String(localized: "Disponible") : copy.statusRaw
        Text(text)
            .font(Typo.sans(11, .semibold, relativeTo: .caption))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(copy.isAvailable ? Palette.available : Palette.onLoan)
            .background(copy.isAvailable ? Palette.availableBg : Palette.onLoanBg, in: Capsule())
            .multilineTextAlignment(.trailing)
    }
}

// MARK: - Three result sections

/// "Bibliotecas Seleccionadas" / "Alternativas Cercanas" / "Otras Bibliotecas" for one edition.
struct GroupedCopiesView: View {
    let copies: [Copy]
    let proximity: Proximity
    var branchFilter: String = ""
    var onlyAvailable = false
    @State private var showOthers = false

    var body: some View {
        let groups = proximity.group(copies)
        let direct = groups.direct.filter(matches)
        let nearby = groups.nearby.filter(matches)
        let other = groups.other.filter(matches)
        let hasSelection = !proximity.selectedLibraries.isEmpty
        let usesOrigin = !hasSelection && proximity.fallbackOrigin != nil

        VStack(alignment: .leading, spacing: 14) {
            if !hasSelection && !usesOrigin {
                rows(copies.filter(matches), distance: false,
                     empty: copies.isEmpty ? "No hay copias físicas registradas para esta edición." : "No hay ejemplares que coincidan con los filtros seleccionados.")
            } else {
                if hasSelection {
                    section("Bibliotecas Seleccionadas (\(direct.count))", color: Palette.accent)
                    rows(direct, distance: false,
                         empty: "No hay ejemplares registrados en las bibliotecas específicamente seleccionadas. Consulte las alternativas cercanas a continuación.")
                }
                section("Alternativas Cercanas (\(nearby.count))", color: Palette.available)
                rows(nearby, distance: true,
                     empty: "No se encontraron sucursales adicionales con copias dentro del radio de búsqueda establecido.")
                if !other.isEmpty {
                    DisclosureGroup(isExpanded: $showOthers) {
                        rows(other, distance: false, empty: "")
                    } label: {
                        Text("Otras Bibliotecas (\(other.count))").eyebrow()
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .tint(Palette.inkSecondary)
                }
            }
        }
    }

    private func matches(_ c: Copy) -> Bool {
        let f = branchFilter.trimmingCharacters(in: .whitespaces).lowercased()
        let byBranch = f.isEmpty || c.library.lowercased().contains(f) || c.location.lowercased().contains(f)
        return byBranch && (!onlyAvailable || c.isAvailable)
    }

    private func section(_ title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).eyebrow().foregroundStyle(Palette.ink)
        }
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func rows(_ list: [Copy], distance: Bool, empty: LocalizedStringKey) -> some View {
        if list.isEmpty {
            Text(empty).font(Typo.sans(12)).foregroundStyle(Palette.inkSecondary).italic()
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.chip, in: RoundedRectangle(cornerRadius: 10))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, copy in
                    if i > 0 { Divider().overlay(Palette.rule) }
                    CopyRow(copy: copy, showDistance: distance)
                }
            }
        }
    }
}

// MARK: - Skeleton

struct SkeletonCard: View {
    @State private var phase = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 6).fill(Palette.chip).frame(width: 64, height: 91)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(Palette.chip).frame(height: 14)
                RoundedRectangle(cornerRadius: 3).fill(Palette.chip).frame(width: 120, height: 10)
                Spacer()
                RoundedRectangle(cornerRadius: 8).fill(Palette.chip).frame(width: 140, height: 20)
            }
        }
        .padding(14)
        .cardStyle()
        .opacity(phase ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(), value: phase)
        .onAppear { phase = true }
        .accessibilityLabel(Text("Comprobando…"))
    }
}

// MARK: - "actualizado hace X"

struct UpdatedAgoLabel: View {
    let date: Date

    var body: some View {
        Label {
            Text("actualizado \(date, format: .relative(presentation: .named))")
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .font(Typo.sans(11, .medium, relativeTo: .caption))
        .foregroundStyle(Palette.inkTertiary)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.sans(14, .bold))
            .foregroundStyle(Palette.paper)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(Palette.ink.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.sans(13, .semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Palette.chip.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}
