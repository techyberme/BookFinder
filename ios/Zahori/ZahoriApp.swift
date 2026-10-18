import SwiftUI

@main
struct ZahoriApp: App {
    @State private var model = AppModel()

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
                .tint(Palette.accent)
                .task {
                    if model.settings.selectedLibraryIDs.isEmpty { model.location.requestIfNeeded() }
                    await model.restore()
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
            LibrarySettingsView()
                .tabItem { Label("Bibliotecas", systemImage: "building.columns") }.tag(2)
        }
        .font(Typo.sans(15))
    }
}

extension RootView {
    /// DEBUG-only screenshot hook: `-ZahoriTab 1` opens a tab, `-ZahoriSearch "title|author"` runs a search.
    static var initialTab: Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "ZahoriTab")
        #else
        return 0
        #endif
    }
}
