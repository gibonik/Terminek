import Foundation
import StoreKit

/// Dlaczego pokazujemy ekran Plus (zmienia nagłówek).
enum PaywallReason: String, Identifiable {
    case documents, scanPages, assistant, reminders, calendar, manual
    var id: String { rawValue }

    var headline: String {
        switch self {
        case .documents: "Masz już \(Store.freeDocuments) dokumentów. Z Plus dodasz ich, ile chcesz."
        case .scanPages: "Skany z wieloma stronami i PDF są w Plus."
        case .assistant: "Dziś wykorzystałeś \(Store.freeAssistantPerDay) darmowe pytania. Z Plus pytasz bez limitu."
        case .reminders: "Własne terminy przypomnień dla każdego dokumentu są w Plus."
        case .calendar: "Dodawanie terminów do Kalendarza jest w Plus."
        case .manual: "Wszystkie dokumenty rodziny pod kontrolą, bez limitów."
        }
    }
}

/// Zakupy (StoreKit 2) i limity darmowego planu. Weryfikacja na telefonie, bez serwera.
///
/// Przy instalacji przez Sideloadly (darmowe Apple ID) produkty się nie wczytają, bo zakupy
/// działają tylko z App Store/TestFlight. Do testów jest „Plus testowy” w ukrytym menu w Koncie.
@MainActor
@Observable
final class Store {
    static let shared = Store()

    static let monthlyID = "pl.terminy.plus.monthly"
    static let yearlyID = "pl.terminy.plus.yearly"
    static let lifetimeID = "pl.terminy.plus.lifetime"
    static let productIDs = [yearlyID, monthlyID, lifetimeID]

    static let freeDocuments = 5
    static let freeScanPages = 1
    static let freeAssistantPerDay = 3

    static let debugPlusKey = "debugPlus"
    static let developerMenuKey = "developerMenu"
    private static let askDayKey = "assistantDay"
    private static let askCountKey = "assistantCount"

    private(set) var products: [Product] = []
    private(set) var purchased: Set<String> = []
    private(set) var loaded = false
    private(set) var busy = false
    var message: String?
    private(set) var debugPlus = UserDefaults.standard.bool(forKey: Store.debugPlusKey)

    private var updates: Task<Void, Never>?

    /// W trybie pokazowym (zrzuty w CI) bez limitów, żeby było widać całą aplikację.
    var isPlus: Bool { debugPlus || !purchased.isEmpty || TerminyApp.isDemo }

    var hasLifetime: Bool { purchased.contains(Self.lifetimeID) }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    func setDebugPlus(_ on: Bool) {
        debugPlus = on
        UserDefaults.standard.set(on, forKey: Self.debugPlusKey)
    }

    // MARK: Start

    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task {
            await loadProducts()
            await refresh()
        }
    }

    func loadProducts() async {
        if TerminyApp.isDemo { loaded = true; return }
        let found = (try? await Product.products(for: Self.productIDs)) ?? []
        products = Self.productIDs.compactMap { id in found.first { $0.id == id } }
        loaded = true
    }

    func refresh() async {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                ids.insert(transaction.productID)
            }
        }
        purchased = ids
    }

    // MARK: Kupno

    func buy(_ product: Product) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refresh()
                Breadcrumbs.add("Zakup: \(product.id)")
                return true
            case .success(.unverified):
                message = "Apple nie potwierdził zakupu. Spróbuj jeszcze raz."
            case .pending:
                message = "Zakup czeka na zatwierdzenie (np. przez rodzica)."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "Nie udało się kupić: \(error.localizedDescription)"
            Log.store.error("Zakup nieudany: \(error.localizedDescription, privacy: .public)")
            Breadcrumbs.add("Zakup nieudany")
        }
        return false
    }

    func restore() async {
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refresh()
            message = isPlus ? "Przywrócono Terminek Plus." : "Nie znaleziono zakupów na tym Apple ID."
        } catch {
            message = "Nie udało się przywrócić zakupów."
        }
    }

    // MARK: Limity

    func canAddDocument(currentCount: Int) -> Bool {
        isPlus || currentCount < Self.freeDocuments
    }

    var maxScanPages: Int { isPlus ? Int.max : Self.freeScanPages }

    /// Pytania do asystenta w darmowym planie: kilka dziennie.
    func assistantQuestionsLeft(now: Date = .now) -> Int {
        guard !isPlus else { return Int.max }
        let defaults = UserDefaults.standard
        let today = Self.dayKey(now)
        let used = defaults.string(forKey: Self.askDayKey) == today ? defaults.integer(forKey: Self.askCountKey) : 0
        return max(0, Self.freeAssistantPerDay - used)
    }

    func recordAssistantQuestion(now: Date = .now) {
        guard !isPlus else { return }
        let defaults = UserDefaults.standard
        let today = Self.dayKey(now)
        let used = defaults.string(forKey: Self.askDayKey) == today ? defaults.integer(forKey: Self.askCountKey) : 0
        defaults.set(today, forKey: Self.askDayKey)
        defaults.set(used + 1, forKey: Self.askCountKey)
    }

    private static func dayKey(_ date: Date) -> String {
        let c = PL.calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
