import Foundation

/// A book currently on loan to the reader ("Mi biblioteca → Préstamos / Renovar").
/// Values come from the OPAC's hidden `varJSONpr` block of each loan.
public struct Loan: Codable, Hashable, Sendable, Identifiable {
    public var barcode: String
    public var title: String
    public var branch: String
    public var branchAddress: String?
    /// "DD/MM/YYYY HH:MM" as printed by the OPAC (`prfdev`), Madrid local time.
    public var dueDateTime: String
    /// "DD/MM/YYYY HH:MM"
    public var loanDateTime: String?
    public var shelfmark: String?
    public var renewalsUsed: Int
    public var renewalsMax: Int
    /// Renewal opens this many days before the due date (`ppdrna`).
    public var renewalWindowDays: Int
    /// Reservations by other readers (`xsresv`); a reserved item cannot be renewed.
    public var reservations: Int
    public var recordURL: String?

    public var id: String { barcode }

    public init(barcode: String, title: String, branch: String, branchAddress: String? = nil, dueDateTime: String,
                loanDateTime: String? = nil, shelfmark: String? = nil, renewalsUsed: Int = 0, renewalsMax: Int = 0,
                renewalWindowDays: Int = 0, reservations: Int = 0, recordURL: String? = nil) {
        self.barcode = barcode
        self.title = title
        self.branch = branch
        self.branchAddress = branchAddress
        self.dueDateTime = dueDateTime
        self.loanDateTime = loanDateTime
        self.shelfmark = shelfmark
        self.renewalsUsed = renewalsUsed
        self.renewalsMax = renewalsMax
        self.renewalWindowDays = renewalWindowDays
        self.reservations = reservations
        self.recordURL = recordURL
    }

    /// "DD/MM/YYYY" part of the due date, as shown to the user.
    public var dueDateText: String { String(dueDateTime.prefix(10)) }

    public var dueDate: Date? { LoanCalendar.parse(dueDateTime) }

    public var hasRenewalsLeft: Bool { renewalsUsed < renewalsMax }

    /// First day renewal is possible (due date − window), or nil if no renewals are left.
    public var renewableFrom: Date? {
        guard hasRenewalsLeft, let due = dueDate else { return nil }
        return LoanCalendar.calendar.date(byAdding: .day, value: -renewalWindowDays,
                                          to: LoanCalendar.calendar.startOfDay(for: due))
    }

    /// Whole days from `now` to the due date (Madrid calendar days). 0 = due today, negative = overdue.
    public func daysUntilDue(from now: Date) -> Int? {
        guard let due = dueDate else { return nil }
        let cal = LoanCalendar.calendar
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day
    }
}

/// Dates on the OPAC are Madrid local time.
public enum LoanCalendar {
    public static let timeZone = TimeZone(identifier: "Europe/Madrid")!

    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = Locale(identifier: "es_ES")
        return c
    }()

    /// "DD/MM/YYYY" in Madrid time, the format the OPAC uses everywhere.
    public static func dayString(_ date: Date) -> String {
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d/%02d/%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }

    /// Parses "DD/MM/YYYY" or "DD/MM/YYYY HH:MM". A date without time means the end of that day.
    public static func parse(_ text: String) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: " ")
        let d = parts.first?.split(separator: "/").compactMap { Int($0) } ?? []
        guard d.count == 3 else { return nil }
        var comps = DateComponents(year: d[2], month: d[1], day: d[0], hour: 23, minute: 59)
        if parts.count > 1 {
            let t = parts[1].split(separator: ":").compactMap { Int($0) }
            if t.count == 2 { comps.hour = t[0]; comps.minute = t[1] }
        }
        return calendar.date(from: comps)
    }
}

/// A local notification to schedule for a loan.
public struct LoanReminder: Hashable, Sendable {
    public enum Kind: String, Sendable { case beforeDue = "before", dueToday = "due" }

    /// Stable id: rescheduling the same loan/due date replaces the old notification.
    public var id: String
    public var barcode: String
    public var kind: Kind
    public var fireDate: Date
    public var title: String
    public var body: String
}

public enum LoanReminders {
    public static let idPrefix = "loan-"

    /// One reminder `daysBefore` days before the due date and one on the due date, both at `hour`
    /// (Madrid time). Reminders already in the past are skipped; overdue loans get none.
    public static func plan(for loans: [Loan], daysBefore: Int, hour: Int = 10, now: Date) -> [LoanReminder] {
        let cal = LoanCalendar.calendar
        var out: [LoanReminder] = []
        for loan in loans {
            guard let due = loan.dueDate else { continue }
            let dueDay = cal.startOfDay(for: due)
            let title = loan.title
            var candidates: [(LoanReminder.Kind, Date, String)] = []
            if daysBefore > 0, let day = cal.date(byAdding: .day, value: -daysBefore, to: dueDay),
               let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) {
                let body = daysBefore == 1
                    ? String(localized: "Mañana vence el préstamo en \(loan.branch).", bundle: .module)
                    : String(localized: "El préstamo vence en \(daysBefore) días (\(loan.dueDateText)) en \(loan.branch).", bundle: .module)
                candidates.append((.beforeDue, fire, body))
            }
            if let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: dueDay) {
                candidates.append((.dueToday, fire, String(localized: "Hoy vence el préstamo en \(loan.branch).", bundle: .module)))
            }
            for (kind, fire, body) in candidates where fire > now {
                out.append(LoanReminder(id: "\(idPrefix)\(loan.barcode)-\(loan.dueDateText)-\(kind.rawValue)",
                                        barcode: loan.barcode, kind: kind, fireDate: fire, title: title, body: body))
            }
        }
        return out.sorted { $0.fireDate < $1.fireDate }
    }
}
