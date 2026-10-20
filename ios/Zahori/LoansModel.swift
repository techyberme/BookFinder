import Foundation
import Observation
import UserNotifications
import ZahoriCore
import ZahoriKit

/// "Mis préstamos": reader login, loans list, offline copy and due-date reminders.
@MainActor @Observable
final class LoansModel {
    private let client = ReaderClient()
    private let store = JSONFileStore<CachedLoans>(filename: "loans.json")

    private(set) var loans: [Loan] = []
    private(set) var fetchedAt: Date?
    private(set) var isLoading = false
    /// Set when the shown loans are the cached copy because the OPAC could not be reached.
    private(set) var showingCachedCopy = false
    var error: String?
    private(set) var hasCredentials: Bool
    private(set) var notificationsDenied = false

    init() {
        hasCredentials = CredentialStore.load() != nil
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ZahoriPreviewLoans") { hasCredentials = true }
        #endif
        if let cached = store.load() {
            loans = cached.loans
            fetchedAt = cached.fetchedAt
        }
    }

    /// Loans sorted by due date, soonest first.
    var sortedLoans: [Loan] {
        loans.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    // MARK: - Login / refresh

    /// Validates the credentials against the OPAC before saving them to the Keychain.
    func connect(card: String, password: String, settings: AppSettings) async {
        let credentials = ReaderCredentials(card: card.trimmingCharacters(in: .whitespaces), password: password)
        guard !credentials.card.isEmpty, !credentials.password.isEmpty else {
            error = String(localized: "Introduce el número de carné y la contraseña.")
            return
        }
        if await refresh(with: credentials, settings: settings) {
            CredentialStore.save(credentials)
            hasCredentials = true
        }
    }

    func refresh(settings: AppSettings) async {
        guard let credentials = CredentialStore.load() else {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "ZahoriPreviewLoans") { return }
            #endif
            hasCredentials = false
            return
        }
        await refresh(with: credentials, settings: settings)
    }

    @discardableResult
    private func refresh(with credentials: ReaderCredentials, settings: AppSettings) async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        defer { isLoading = false }

        switch await client.fetchLoans(credentials) {
        case let .success(loans):
            self.loans = loans
            fetchedAt = Date()
            showingCachedCopy = false
            error = nil
            try? store.save(CachedLoans(loans: loans, fetchedAt: fetchedAt!))
            await scheduleReminders(settings: settings)
            return true
        case .failure(.invalidCredentials):
            error = String(localized: "El número de carné o la contraseña no son correctos. Recuerda que la contraseña del catálogo caduca a los 6 meses.")
            return false
        case let .failure(.catalogUnavailable(reason)):
            showingCachedCopy = fetchedAt != nil
            error = String(localized: "No se pudieron consultar tus préstamos: \(reason)")
            return false
        }
    }

    /// Forgets the card and password, the cached loans and all scheduled reminders.
    func disconnect() {
        CredentialStore.delete()
        store.delete()
        hasCredentials = false
        loans = []
        fetchedAt = nil
        error = nil
        showingCachedCopy = false
        Task { await removeAllReminders() }
    }

    // MARK: - Reminders

    func scheduleReminders(settings: AppSettings) async {
        await removeAllReminders()
        guard settings.loanRemindersEnabled, !loans.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationsDenied = !granted
        guard granted else { return }

        for reminder in LoanReminders.plan(for: loans, daysBefore: settings.reminderDaysBefore, now: Date()) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            var comps = LoanCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            comps.timeZone = LoanCalendar.timeZone
            let request = UNNotificationRequest(identifier: reminder.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(request)
        }
    }

    private func removeAllReminders() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(LoanReminders.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
