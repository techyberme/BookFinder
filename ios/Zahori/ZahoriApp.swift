import SwiftUI

@main
struct ZahoriApp: App {
    @State private var model = AppModel()
    @State private var loans = LoansModel()

    init() {
        // Editorial navigation titles: Fraunces for large titles, Plus Jakarta Sans for inline ones.
        // Only fonts are changed; bar backgrounds stay system-managed (custom appearances hide large titles on iOS 26).
        let bar = UINavigationBar.appearance()
        if let large = UIFont(name: "Fraunces-Bold", size: 34), let inline = UIFont(name: "PlusJakartaSans-Bold", size: 17) {
            bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
            bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline)]
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(loans)
                .tint(Palette.accent)
                .task {
                    if model.settings.selectedLibraryIDs.isEmpty { model.location.requestIfNeeded() }
                    async let shelf: Void = model.restore()
                    async let reader: Void = loans.refresh(settings: model.settings)
                    _ = await (shelf, reader)
                }
        }
    }
}

struct RootView: View {
    @State private var tab = RootView.initialTab

    var body: some View {
        TabView(selection: $tab) {
            ShelfView()
                .tabItem { Label("Estantería", systemImage: "books.vertical") }.tag(0)
            SearchView()
                .tabItem { Label("Buscar", systemImage: "magnifyingglass") }.tag(1)
            LoansView()
                .tabItem { Label("Préstamos", systemImage: "calendar.badge.clock") }.tag(3)
            LibrarySettingsView()
                .tabItem { Label("Bibliotecas", systemImage: "building.columns") }.tag(2)
        }
        .font(Typo.sans(15))
    }
}

extension RootView {
    /// DEBUG-only screenshot hooks: `-ZahoriTab n` opens a tab (0 shelf, 1 search, 3 loans, 2 libraries),
    /// `-ZahoriSearch "title|author"` runs a search, `-ZahoriPreviewLoans YES` shows the cached loans without a login.
    static var initialTab: Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "ZahoriTab")
        #else
        return 0
        #endif
    }
}
