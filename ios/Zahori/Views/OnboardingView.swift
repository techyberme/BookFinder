import SwiftUI
import ZahoriKit

/// Screen 5: empty state asking for a Goodreads user ID ("Conecta tu estantería de Goodreads").
struct OnboardingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Zahorí").eyebrow().foregroundStyle(Palette.accent)
                    Text("Conecta tu estantería de Goodreads").font(Typo.serif(30)).foregroundStyle(Palette.ink)
                    Text("Comprueba automáticamente la disponibilidad de los libros de tu lista en las bibliotecas públicas de Madrid.")
                        .font(Typo.sans(15)).foregroundStyle(Palette.inkSecondary)
                }
                ProfileForm()
                    .padding(16)
                    .cardStyle()
            }
            .padding(16)
        }
    }
}

/// Shared by onboarding and the profile sheet. Port of the "Perfil de Goodreads" modal.
struct ProfileForm: View {
    @Environment(AppModel.self) private var model
    @State private var userInput = ""
    @State private var shelf = "to-read"
    var onDone: (() -> Void)?

    private let shelves = ["to-read", "currently-reading", "read"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ID de usuario o enlace de perfil").eyebrow()
                TextField(text: $userInput, prompt: Text(verbatim: "155193797-javier-bermejo · goodreads.com/user/show/…")) { Text("ID de usuario o enlace de perfil") }
                    .font(Typo.sans(15))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.rule))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Estantería (shelf)").eyebrow()
                HStack(spacing: 8) {
                    TextField("to-read, currently-reading, read...", text: $shelf)
                        .font(Typo.mono(14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.rule))
                    Menu {
                        ForEach(shelves, id: \.self) { s in Button(s) { shelf = s } }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Elegir estantería"))
                }
            }
            if let error = model.shelfError, !model.hasProfile {
                Text(error).font(Typo.sans(12, .medium)).foregroundStyle(Palette.accent)
            }
            Button {
                Task {
                    await model.connect(userInput: userInput, shelf: shelf)
                    if model.hasProfile { onDone?() }
                }
            } label: {
                HStack {
                    if model.isLoadingShelf { ProgressView().tint(Palette.paper) }
                    Text("Sincronizar")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isLoadingShelf)

            Button("Cargar cuenta demo") {
                userInput = "177587843"
                shelf = "to-read"
                Task {
                    await model.connect(userInput: userInput, shelf: shelf)
                    if model.hasProfile { onDone?() }
                }
            }
            .font(Typo.sans(13, .semibold)).foregroundStyle(Palette.inkSecondary).frame(minHeight: 44)
        }
        .onAppear {
            userInput = model.settings.goodreadsUserID ?? ""
            shelf = model.settings.shelf
        }
    }
}

struct ProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Sincroniza tu lista de lectura con las bibliotecas").font(Typo.sans(14)).foregroundStyle(Palette.inkSecondary)
                    ProfileForm(onDone: { dismiss() })
                    Button(role: .destructive) {
                        Task { await model.disconnect(); dismiss() }
                    } label: {
                        Text("Desconectar perfil").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(16)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Perfil de Goodreads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
    }
}
