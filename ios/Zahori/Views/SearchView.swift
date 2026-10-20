import SwiftUI
import ZahoriCore

/// Screen 4: direct catalog search by title/author ("Búsqueda Directa en Catálogo").
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var title = ""
    @State private var author = ""
    @State private var validationError: String?
    @State private var branchFilter = ""
    @State private var onlyAvailable = false
    @FocusState private var focused: Field?

    enum Field { case title, author }

    /// Same quick-fill examples as frontend/index.html.
    private let suggestions = [
        ("Cien años de soledad", "Gabriel García Márquez"),
        ("El infinito en un junco", "Irene Vallejo"),
        ("Ficciones", "Jorge Luis Borges"),
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        form
                        results
                    }
                    .padding(16)
                }
                #if DEBUG
                .onChange(of: model.searchResult) { _, _ in
                    // Screenshot hook: `-ZahoriScrollTo sections` jumps to the first edition's copy sections.
                    if UserDefaults.standard.string(forKey: "ZahoriScrollTo") == "sections" {
                        Task { try? await Task.sleep(nanoseconds: 300_000_000); proxy.scrollTo("sections-0", anchor: .top) }
                    }
                }
                #endif
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Buscar")
            #if DEBUG
            .task {
                if let q = UserDefaults.standard.string(forKey: "ZahoriSearch"), model.searchResult == nil {
                    let parts = q.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                    title = parts[0]; author = parts.count > 1 ? parts[1] : ""
                    submit()
                }
            }
            #endif
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Consulte la disponibilidad física en sala, sucursales y fechas estimadas de devolución en toda la red pública.")
                .font(Typo.sans(13)).foregroundStyle(Palette.inkSecondary)
            field("Título del libro", text: $title, prompt: "Ej: Cien años de soledad, Don Quijote…", which: .title)
            field("Autor / Autora", text: $author, prompt: "Ej: García Márquez, Irene Vallejo, J.K. Rowling…", which: .author)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.0) { s in
                        Button(s.0) { title = s.0; author = s.1 }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }

            if let validationError {
                Text(validationError).font(Typo.sans(12, .medium)).foregroundStyle(Palette.accent)
            }

            HStack(spacing: 10) {
                Button("Limpiar") {
                    title = ""; author = ""; validationError = nil; model.searchResult = nil
                }
                .buttonStyle(SecondaryButtonStyle())
                Button(action: submit) {
                    HStack {
                        if model.isSearching { ProgressView().tint(Palette.paper) }
                        Text("Consultar catálogo")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isSearching)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func field(_ label: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey, which: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).eyebrow()
            TextField(prompt, text: text)
                .font(Typo.sans(15))
                .focused($focused, equals: which)
                .submitLabel(which == .title ? .next : .search)
                .onSubmit { which == .title ? (focused = .author) : submit() }
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.rule))
        }
    }

    private func submit() {
        let t = title.trimmingCharacters(in: .whitespaces), a = author.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty || !a.isEmpty else {
            validationError = String(localized: "Por favor, introduzca al menos un título o un autor para realizar la búsqueda.")
            focused = .title
            return
        }
        validationError = nil
        focused = nil
        Task { await model.search(title: t, author: a) }
    }

    @ViewBuilder private var results: some View {
        if model.isSearching {
            ForEach(0..<2, id: \.self) { _ in SkeletonCard() }
        } else if let result = model.searchResult {
            switch result.outcome {
            case let .catalogUnavailable(reason):
                CatalogUnavailableView(reason: reason, retry: submit)
            case .noResults, .invalidQuery:
                emptyState
            case .found:
                if result.editions.isEmpty { emptyState } else { found(result) }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No se encontraron ejemplares").font(Typo.serif(18)).foregroundStyle(Palette.ink)
            Text("No se recuperaron resultados en el catálogo con los términos indicados. Pruebe a buscar por solo el título principal o por el autor.")
                .font(Typo.sans(13)).foregroundStyle(Palette.inkSecondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardStyle()
    }

    private func found(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                (result.totalEditions == 1 ? Text("1 edición") : Text("\(result.totalEditions) ediciones"))
                Text("•")
                (result.totalCopies == 1 ? Text("1 ejemplar en red") : Text("\(result.totalCopies) ejemplares en red"))
                Text("•")
                (result.totalAvailableCopies == 1 ? Text("1 disponible") : Text("\(result.totalAvailableCopies) disponibles"))
                    .foregroundStyle(Palette.available)
            }
            .font(Typo.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)

            HStack(spacing: 10) {
                TextField("Filtrar por biblioteca...", text: $branchFilter)
                    .font(Typo.sans(14)).padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.rule))
                Toggle(isOn: $onlyAvailable) { Text("Solo disponibles").font(Typo.sans(12, .semibold)) }
                    .toggleStyle(.button).tint(Palette.available).frame(minHeight: 44)
            }

            ForEach(Array(result.editions.enumerated()), id: \.offset) { i, edition in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Edición #\(i + 1)").eyebrow()
                        Spacer()
                        (edition.totalCopies == 1 ? Text("\(edition.availableCopies) de 1 disponible") : Text("\(edition.availableCopies) de \(edition.totalCopies) disponibles"))
                            .font(Typo.sans(11, .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(edition.availableCopies > 0 ? Palette.available : Palette.inkSecondary)
                            .background(edition.availableCopies > 0 ? Palette.availableBg : Palette.chip, in: Capsule())
                    }
                    Text(edition.title).font(Typo.serif(18)).foregroundStyle(Palette.ink)
                    if let author = edition.author, !author.isEmpty {
                        Text(author).font(Typo.sans(13, .medium)).foregroundStyle(Palette.inkSecondary)
                    }
                    EditionMeta(edition: edition)
                    Divider().overlay(Palette.rule)
                    GroupedCopiesView(copies: edition.copies, proximity: model.proximity,
                                      branchFilter: branchFilter, onlyAvailable: onlyAvailable)
                        .id("sections-\(i)")
                }
                .padding(16)
                .cardStyle()
            }
            if case .found(_, _, true) = result.outcome {
                Label("Algunas ediciones no se pudieron cargar del catálogo.", systemImage: "exclamationmark.triangle")
                    .font(Typo.sans(12)).foregroundStyle(Palette.onLoan)
            }
        }
    }
}
