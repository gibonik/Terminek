import Foundation
import SwiftData

/// Jeden dokument z terminem ważności.
///
/// Zasady modelu pod synchronizację CloudKit:
/// - każde pole ma wartość domyślną albo jest opcjonalne,
/// - brak `@Attribute(.unique)`,
/// - duże dane (skan) w `.externalStorage`.
@Model
final class Document {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = DocumentCategory.other.rawValue
    var expiryDate: Date = Date.now
    /// Do kogo należy dokument (np. „Ja”, „Ania”, „Passat”).
    var owner: String = ""
    var number: String = ""
    var notes: String = ""
    var remindersEnabled: Bool = true
    /// Własne terminy przypomnień (dni przed), np. "60,14,3". Puste = jak w ustawieniach.
    var customOffsetsRaw: String = ""
    var createdAt: Date = Date.now

    // Tylko dla subskrypcji
    var price: Double?
    var billingCycleRaw: String?

    /// Miniatura pierwszej strony skanu (lista, karta, podgląd).
    @Attribute(.externalStorage) var scanImageData: Data?
    /// Wszystkie strony skanu w jednym PDF-ie.
    @Attribute(.externalStorage) var scanPDFData: Data?
    var scanPageCount: Int = 0

    init(
        title: String = "",
        category: DocumentCategory = .other,
        expiryDate: Date = .now,
        owner: String = "",
        number: String = "",
        notes: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.categoryRaw = category.rawValue
        self.expiryDate = expiryDate
        self.owner = owner
        self.number = number
        self.notes = notes
        self.createdAt = .now
    }

    var category: DocumentCategory {
        get { DocumentCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var billingCycle: BillingCycle? {
        get { billingCycleRaw.flatMap(BillingCycle.init(rawValue:)) }
        set { billingCycleRaw = newValue?.rawValue }
    }

    /// Własne przypomnienia tego dokumentu albo `nil`, gdy obowiązują ustawienia ogólne.
    var customOffsets: [Int]? {
        get {
            let values = customOffsetsRaw.split(separator: ",").compactMap { Int($0) }
            return values.isEmpty ? nil : Array(Set(values)).sorted(by: >)
        }
        set {
            customOffsetsRaw = Set(newValue ?? []).sorted(by: >).map(String.init).joined(separator: ",")
        }
    }

    var displayTitle: String {
        title.isEmpty ? category.title : title
    }

    /// Liczba pełnych dni do końca ważności (ujemna = po terminie).
    func daysLeft(from now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: expiryDate)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    func status(from now: Date = .now) -> ExpiryStatus {
        ExpiryStatus(daysLeft: daysLeft(from: now))
    }

    /// Przesuwa termin o typowy okres (lub cykl rozliczeniowy subskrypcji).
    /// Liczy od starego terminu, a jeśli ten już minął, od dziś.
    func renew(now: Date = .now, calendar: Calendar = .current) {
        expiryDate = renewedExpiryDate(now: now, calendar: calendar)
    }

    func renewedExpiryDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        let period = (category == .subscription ? billingCycle?.components : nil) ?? category.defaultRenewal
        let base = max(expiryDate, calendar.startOfDay(for: now))
        return calendar.date(byAdding: period, to: base) ?? expiryDate
    }
}

enum ExpiryStatus: Comparable {
    case expired
    case soon      // ≤ 30 dni
    case ok

    init(daysLeft: Int) {
        switch daysLeft {
        case ..<0: self = .expired
        case 0...30: self = .soon
        default: self = .ok
        }
    }

    var sectionTitle: String {
        switch self {
        case .expired: "Po terminie"
        case .soon: "Wkrótce (do 30 dni)"
        case .ok: "Ważne"
        }
    }
}
