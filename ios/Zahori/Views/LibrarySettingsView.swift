import SwiftUI
import ZahoriCore
import ZahoriKit

/// Screen 3: reference libraries (multi-select) and proximity radius ("Bibliotecas Preferidas & Radio").
struct LibrarySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var radiusText = ""
    @FocusState private var radiusFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    radiusControl
                } header: {
                    Text("Radio de proximidad").eyebrow()
                } footer: {
                    Text("Recomienda sucursales alternativas dentro del radio.").font(Typo.sans(12))
                }

                Section {
                    if model.selectedLibraries.isEmpty {
                        Text("Ninguna seleccionada: las distancias se miden desde \(model.location.origin.name).")
                            .font(Typo.sans(13)).italic().foregroundStyle(Palette.inkSecondary)
                        locationRow
                    }
                    ForEach(model.selectedLibraries) { lib in
                        libraryRow(lib, selected: true)
                    }
                } header: {
                    Text("Bibliotecas de referencia").eyebrow()
                }

                Section {
                    ForEach(filtered) { lib in libraryRow(lib, selected: false) }
                } header: {
                    Text("Red de bibliotecas").eyebrow()
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .searchable(text: $query, prompt: Text("Buscar bibliotecas (ej: Eugenio Trías, Retiro…)"))
            .navigationTitle("Bibliotecas")
            .onAppear { radiusText = String(model.settings.radiusKm) }
            .onChange(of: model.settings.radiusKm) { _, new in
                if !radiusFocused { radiusText = String(new) }
            }
        }
    }

    /// Port of `filterAndRenderDropdown`: name / district / municipality contains, excluding selected.
    private var filtered: [Library] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let selected = Set(model.settings.selectedLibraryIDs)
        return model.directory.sortedList.filter { lib in
            guard !selected.contains(lib.id) else { return false }
            return q.isEmpty || lib.name.lowercased().contains(q) || lib.district.lowercased().contains(q)
                || lib.municipality.lowercased().contains(q)
        }
    }

    // Two-way sync: the slider writes the setting (and the field follows via onChange); the field writes
    // the setting while typing when the value is a number, and clamps on submit/blur like the web input.
    private var radiusControl: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("5", text: $radiusText)
                    .keyboardType(.numberPad)
                    .focused($radiusFocused)
                    .font(Typo.mono(20, .semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64, height: 44)
                    .background(Palette.chip, in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: radiusText) { _, text in
                        if let v = Int(text) { model.settings.radiusKm = AppSettings.clampRadius(v) }
                    }
                    .onSubmit(commitRadiusText)
                    .onChange(of: radiusFocused) { _, focused in if !focused { commitRadiusText() } }
                    .accessibilityLabel(Text("Radio en kilómetros"))
                Text("km").font(Typo.sans(15, .semibold))
                Spacer()
            }
            Slider(value: Binding(
                get: { Double(model.settings.radiusKm) },
                set: { model.settings.radiusKm = AppSettings.clampRadius(Int($0.rounded())) }
            ), in: 1...20, step: 1) {
                Text("Radio de proximidad")
            } minimumValueLabel: {
                Text("1 km").font(Typo.mono(11))
            } maximumValueLabel: {
                Text("20 km").font(Typo.mono(11))
            }
            .tint(Palette.accent)
            .frame(minHeight: 44)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { radiusFocused = false }
            }
        }
    }

    /// Web `blur` handler: invalid or < 1 → 1, > 20 → 20.
    private func commitRadiusText() {
        let v = AppSettings.clampRadius(Int(radiusText) ?? 1)
        model.settings.radiusKm = v
        radiusText = String(v)
    }

    @ViewBuilder private var locationRow: some View {
        if model.location.coordinate == nil {
            Button {
                model.location.requestIfNeeded()
            } label: {
                Label(model.location.isDenied ? "Ubicación denegada: se usa el centro de Madrid" : "Usar mi ubicación",
                      systemImage: model.location.isDenied ? "location.slash" : "location")
                    .font(Typo.sans(14, .semibold)).frame(minHeight: 44)
            }
            .disabled(model.location.isDenied)
            .tint(Palette.accent)
        }
    }

    private func libraryRow(_ lib: Library, selected: Bool) -> some View {
        Button {
            model.toggleLibrary(lib.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(selected ? Palette.accent : Palette.inkTertiary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lib.name).font(Typo.sans(14, .bold)).foregroundStyle(Palette.ink)
                    Text("\(lib.district) • \(lib.municipality)").font(Typo.sans(12)).foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Palette.card)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(Text(selected ? "Quitar" : "Añadir"))
    }
}
