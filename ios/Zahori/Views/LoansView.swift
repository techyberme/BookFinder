import SwiftUI
import ZahoriCore
import ZahoriKit

/// "Préstamos": the reader's current loans and due-date reminders.
struct LoansView: View {
    @Environment(AppModel.self) private var model
    @Environment(LoansModel.self) private var loans

    var body: some View {
        NavigationStack {
            Group {
                if loans.hasCredentials {
                    list
                } else {
                    ScrollView { ReaderLoginForm().padding(16) }
                }
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Préstamos")
            .toolbar {
                if loans.hasCredentials {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { Task { await loans.refresh(settings: model.settings) } } label: {
                                Label("Actualizar", systemImage: "arrow.clockwise")
                            }
                            Button(role: .destructive) { loans.disconnect() } label: {
                                Label("Cerrar sesión y olvidar el carné", systemImage: "person.crop.circle.badge.xmark")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(Text("Opciones"))
                    }
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let error = loans.error {
                    ErrorBanner(message: error, cachedAt: loans.showingCachedCopy ? loans.fetchedAt : nil)
                }
                HStack {
                    (loans.loans.count == 1 ? Text("1 préstamo") : Text("\(loans.loans.count) préstamos"))
                        .font(Typo.sans(13, .semibold)).foregroundStyle(Palette.inkSecondary)
                    Spacer()
                    if loans.isLoading {
                        ProgressView()
                    } else if let date = loans.fetchedAt {
                        UpdatedAgoLabel(date: date)
                    }
                }
                if loans.loans.isEmpty && !loans.isLoading {
                    Text("No tienes libros en préstamo ahora mismo.")
                        .font(Typo.sans(14)).foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity).padding(24).cardStyle()
                }
                ForEach(loans.sortedLoans) { LoanCard(loan: $0) }
                ReminderSettings()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await loans.refresh(settings: model.settings) }
    }
}

// MARK: - Login

struct ReaderLoginForm: View {
    @Environment(AppModel.self) private var model
    @Environment(LoansModel.self) private var loans
    @State private var card = ""
    @State private var password = ""
    @FocusState private var field: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mi biblioteca").eyebrow().foregroundStyle(Palette.accent)
                Text("Tus préstamos, siempre a mano").font(Typo.serif(28)).foregroundStyle(Palette.ink)
                Text("Conéctate con tu carné de la Red de Bibliotecas para ver qué tienes en préstamo y recibir un aviso antes de cada fecha de devolución.")
                    .font(Typo.sans(15)).foregroundStyle(Palette.inkSecondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                labeled("Nº de carné") {
                    TextField(text: $card, prompt: Text(verbatim: "0000000000")) { Text("Nº de carné") }
                        .font(Typo.mono(16)).keyboardType(.asciiCapable)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($field, equals: 0).submitLabel(.next).onSubmit { field = 1 }
                }
                labeled("Contraseña") {
                    SecureField(text: $password, prompt: Text(verbatim: "••••••••")) { Text("Contraseña") }
                        .font(Typo.sans(16)).textContentType(.password)
                        .focused($field, equals: 1).submitLabel(.go).onSubmit(submit)
                }
                if let error = loans.error {
                    Text(error).font(Typo.sans(12, .medium)).foregroundStyle(Palette.accent)
                }
                Button(action: submit) {
                    HStack {
                        if loans.isLoading { ProgressView().tint(Palette.paper) }
                        Text("Conectar")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(loans.isLoading)
            }
            .padding(16)
            .cardStyle()

            Label {
                Text("El carné y la contraseña se guardan solo en este iPhone, en el Llavero, y únicamente se envían al catálogo de la Comunidad de Madrid. Puedes borrarlos en cualquier momento.")
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(Typo.sans(12)).foregroundStyle(Palette.inkSecondary)
        }
    }

    private func labeled(_ label: LocalizedStringKey, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).eyebrow()
            content()
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.rule))
        }
    }

    private func submit() {
        field = nil
        Task { await loans.connect(card: card, password: password, settings: model.settings) }
    }
}

// MARK: - Loan card

struct LoanCard: View {
    let loan: Loan

    var body: some View {
        let days = loan.daysUntilDue(from: Date())
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                dueBadge(days)
                Spacer()
                Text(loan.dueDateText).font(Typo.mono(13, .semibold)).foregroundStyle(Palette.ink)
                    .accessibilityLabel(Text("Devolver antes del \(loan.dueDateText)"))
            }
            Text(loan.title).font(Typo.serif(19)).foregroundStyle(Palette.ink)
            Label(loan.branch, systemImage: "building.columns")
                .font(Typo.sans(13, .semibold)).foregroundStyle(Palette.inkSecondary)
            HStack(spacing: 8) {
                if let sign = loan.shelfmark {
                    Text(sign).font(Typo.mono(12, .semibold)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Palette.chip, in: RoundedRectangle(cornerRadius: 4))
                }
                Label("\(loan.renewalsUsed)/\(loan.renewalsMax)", systemImage: "arrow.triangle.2.circlepath")
                    .font(Typo.mono(12)).foregroundStyle(Palette.inkSecondary)
                    .accessibilityLabel(Text("Renovaciones: \(loan.renewalsUsed) de \(loan.renewalsMax)"))
                if loan.reservations > 0 {
                    Label(loan.reservations == 1 ? "1 reserva" : "\(loan.reservations) reservas", systemImage: "person.2")
                        .font(Typo.sans(12, .semibold)).foregroundStyle(Palette.onLoan)
                }
            }
            if let note = renewalNote {
                Text(note).font(Typo.sans(12)).foregroundStyle(Palette.inkTertiary)
            }
        }
        .padding(14)
        .cardStyle()
    }

    @ViewBuilder private func dueBadge(_ days: Int?) -> some View {
        let (text, fg, bg): (LocalizedStringKey, Color, Color) = {
            guard let d = days else { return ("Fecha desconocida", Palette.inkSecondary, Palette.chip) }
            switch d {
            case ..<0: return (d == -1 ? "Venció ayer" : "Vencido hace \(-d) días", Palette.accent, Palette.accentBg)
            case 0: return ("Vence hoy", Palette.accent, Palette.accentBg)
            case 1: return ("Vence mañana", Palette.onLoan, Palette.onLoanBg)
            case 2...5: return ("Vence en \(d) días", Palette.onLoan, Palette.onLoanBg)
            default: return ("Quedan \(d) días", Palette.available, Palette.availableBg)
            }
        }()
        Text(text)
            .font(Typo.sans(11, .bold, relativeTo: .caption)).textCase(.uppercase).tracking(0.6)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(fg).background(bg, in: Capsule())
    }

    /// Mirrors the OPAC rule: renewable N days before the due date, if not reserved and under the limit.
    private var renewalNote: String? {
        if loan.reservations > 0 { return String(localized: "Reservado por otros lectores: no se podrá renovar.") }
        guard let from = loan.renewableFrom else {
            return loan.renewalsMax > 0 ? String(localized: "Ya no quedan renovaciones.") : nil
        }
        let date = LoanCalendar.dayString(from)
        return from <= Date()
            ? String(localized: "Ya se puede renovar en el catálogo.")
            : String(localized: "Renovable en el catálogo desde el \(date).")
    }
}

// MARK: - Reminder settings

struct ReminderSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(LoansModel.self) private var loans

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Text("Avisos de devolución").eyebrow()
            Toggle(isOn: $model.settings.loanRemindersEnabled) {
                Text("Avisarme antes de cada fecha").font(Typo.sans(14, .semibold))
            }
            .tint(Palette.accent).frame(minHeight: 44)
            if model.settings.loanRemindersEnabled {
                Stepper(value: $model.settings.reminderDaysBefore, in: AppSettings.reminderDaysRange) {
                    (model.settings.reminderDaysBefore == 1 ? Text("1 día antes, a las 10:00") : Text("\(model.settings.reminderDaysBefore) días antes, a las 10:00"))
                        .font(Typo.sans(14))
                }
                .frame(minHeight: 44)
                Text("También recibirás un aviso el mismo día de la devolución.")
                    .font(Typo.sans(12)).foregroundStyle(Palette.inkSecondary)
            }
            if loans.notificationsDenied {
                Label("Las notificaciones están desactivadas para Zahorí en Ajustes.", systemImage: "bell.slash")
                    .font(Typo.sans(12, .medium)).foregroundStyle(Palette.accent)
            }
        }
        .padding(16)
        .cardStyle()
        .onChange(of: model.settings.loanRemindersEnabled) { _, _ in Task { await loans.scheduleReminders(settings: model.settings) } }
        .onChange(of: model.settings.reminderDaysBefore) { _, _ in Task { await loans.scheduleReminders(settings: model.settings) } }
    }
}
