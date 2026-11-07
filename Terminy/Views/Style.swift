import SwiftUI
import UIKit

// MARK: - Kolory
//
// Wszystkie kolory są w `DesignTokens`. Tu zostaje tylko pomocniczy inicjalizator.

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Polskie daty i kwoty

/// Polskie nazwy i daty niezależnie od języka telefonu (cała appka jest po polsku).
enum PL {
    static let locale = Locale(identifier: "pl_PL")

    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        cal.firstWeekday = 2
        return cal
    }

    /// Mianownik: „Listopad”.
    static let months = ["Styczeń", "Luty", "Marzec", "Kwiecień", "Maj", "Czerwiec",
                         "Lipiec", "Sierpień", "Wrzesień", "Październik", "Listopad", "Grudzień"]
    static let weekdays = ["pn", "wt", "śr", "cz", "pt", "sb", "nd"]

    /// „13 listopada 2026”.
    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }

    /// „piątek, 13 listopada”.
    static func dayAndMonth(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    /// „13 listopada”.
    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(locale))
    }

    /// „13.11.2026”.
    static func numeric(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(locale))
    }

    /// Skrót dnia tygodnia: „pt”.
    static func weekday(_ date: Date) -> String {
        let index = (calendar.component(.weekday, from: date) + 5) % 7
        return weekdays[index]
    }

    static func monthName(_ date: Date) -> String {
        months[calendar.component(.month, from: date) - 1]
    }

    /// „1 strona”, „3 strony”, „5 stron”.
    static func pages(_ n: Int) -> String {
        let ones = n % 10, tens = n % 100
        let word = n == 1 ? "strona" : (2...4).contains(ones) && !(12...14).contains(tens) ? "strony" : "stron"
        return "\(n) \(word)"
    }

    static func money(_ value: Double) -> String {
        let rounded = value.rounded()
        let digits = abs(value - rounded) < 0.005 ? 0 : 2
        return value.formatted(.number.precision(.fractionLength(digits)).locale(locale)) + " zł"
    }
}

// MARK: - Grupy kategorii

enum CategoryGroup: String, CaseIterable, Identifiable {
    case auto, home, personal, subscriptions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .home: "Dom"
        case .personal: "Osobiste"
        case .subscriptions: "Abonamenty"
        }
    }

    /// Gradient karty dokumentu.
    var gradient: [Color] {
        switch self {
        case .auto: DT.Palette.Card.auto
        case .home: DT.Palette.Card.home
        case .personal: DT.Palette.Card.personal
        case .subscriptions: DT.Palette.Card.subscriptions
        }
    }

    /// Jeden kolor grupy (kropki w kalendarzu, ikony).
    var color: Color { gradient[0] }

    /// Tekst na karcie.
    var ink: Color { DT.Palette.Card.ink }

    var symbol: String {
        switch self {
        case .auto: "car"
        case .home: "house"
        case .personal: "person.text.rectangle"
        case .subscriptions: "arrow.triangle.2.circlepath"
        }
    }

    var categories: [DocumentCategory] {
        DocumentCategory.allCases.filter { $0.group == self }
    }
}

extension DocumentCategory {
    /// Gradient karty tego rodzaju dokumentu.
    var cardGradient: [Color] {
        switch self {
        case .carInsurance: DT.Palette.Card.carInsurance
        case .carInspection: DT.Palette.Card.carInspection
        case .passport: DT.Palette.Card.passport
        case .idCard: DT.Palette.Card.idCard
        case .drivingLicense: DT.Palette.Card.drivingLicense
        case .homeInsurance: DT.Palette.Card.homeInsurance
        case .subscription: DT.Palette.Card.subscription
        case .other: DT.Palette.Card.other
        }
    }

    /// Kolor tekstu na karcie.
    var cardInk: Color {
        switch self {
        case .carInspection: DT.Palette.Card.carInspectionInk
        case .passport: DT.Palette.Card.passportInk
        case .idCard: DT.Palette.Card.idCardInk
        case .drivingLicense: DT.Palette.Card.drivingLicenseInk
        default: DT.Palette.Card.ink
        }
    }

    /// Gradient animowanego baneru i tła szczegółów (zawsze z białym tekstem).
    var heroGradient: [Color] {
        switch self {
        case .idCard: DT.Palette.Card.idCardHero
        case .drivingLicense: DT.Palette.Card.drivingLicenseHero
        case .carInspection: DT.Palette.Card.carInspectionHero
        case .subscription: DT.Palette.Card.subscriptionGlow
        default: cardGradient
        }
    }

    /// Kolor do poświaty i kropek.
    var cardGlow: Color {
        self == .subscription ? DT.Palette.Card.subscriptionGlow[0] : cardGradient[0]
    }

    /// Napis na karcie, jak na prawdziwym dokumencie.
    var cardLabel: String {
        switch self {
        case .carInsurance: "POLISA OC"
        case .carInspection: "BADANIE TECHNICZNE"
        case .passport: "PASZPORT · PASSPORT"
        case .idCard: "DOWÓD OSOBISTY"
        case .drivingLicense: "PRAWO JAZDY"
        case .homeInsurance: "POLISA MIESZKANIA"
        case .subscription: "SUBSKRYPCJA"
        case .other: "DOKUMENT"
        }
    }

    var group: CategoryGroup {
        switch self {
        case .carInsurance, .carInspection, .drivingLicense: .auto
        case .homeInsurance, .other: .home
        case .passport, .idCard: .personal
        case .subscription: .subscriptions
        }
    }

    /// Podpowiedź w polu nazwy.
    var titlePlaceholder: String {
        switch self {
        case .carInsurance: "np. OC Passat"
        case .carInspection: "np. Przegląd Passat"
        case .passport: "np. Paszport Ani"
        case .idCard: "np. Dowód osobisty"
        case .drivingLicense: "np. Prawo jazdy"
        case .homeInsurance: "np. Polisa mieszkania"
        case .subscription: "np. Netflix"
        case .other: "np. Gwarancja pralki"
        }
    }

    var ownerLabel: String {
        switch self {
        case .carInsurance, .homeInsurance: "Ubezpieczyciel"
        case .carInspection: "Samochód"
        case .subscription: "Konto"
        default: "Czyj"
        }
    }

    var numberLabel: String {
        switch self {
        case .carInsurance, .homeInsurance: "Numer polisy"
        case .carInspection: "Rejestracja"
        case .passport, .idCard, .drivingLicense: "Numer dokumentu"
        default: "Numer"
        }
    }
}

extension Document {
    var group: CategoryGroup { category.group }

    /// Koszt miesięczny subskrypcji.
    var monthlyCost: Double {
        guard category == .subscription, let price else { return 0 }
        switch billingCycle ?? .monthly {
        case .monthly: return price
        case .quarterly: return price / 3
        case .yearly: return price / 12
        }
    }

    /// Druga linijka wiersza: cena, właściciel albo numer.
    var detailLine: String {
        if category == .subscription, let price {
            return PL.money(price) + " / " + (billingCycle ?? .monthly).shortTitle
        }
        if !owner.isEmpty { return owner }
        if !number.isEmpty { return number }
        return category.title
    }
}

extension BillingCycle {
    var shortTitle: String {
        switch self {
        case .monthly: "mies."
        case .quarterly: "kwartał"
        case .yearly: "rok"
        }
    }
}

// MARK: - Teksty dni

/// „6 dni”, „dziś”, „2 dni po”, „4 lata”.
enum DaysText {
    static func short(_ days: Int) -> String {
        switch days {
        case ..<0: return "\(-days) \(dni(-days)) po"
        case 0: return "dziś"
        case 1: return "jutro"
        case 2...365: return "\(days) dni"
        default:
            let years = days / 365
            return "\(years) \(lata(years))"
        }
    }

    /// Zdanie do szczegółów: „za 6 dni”, „2 dni temu”, „dziś”.
    static func sentence(_ days: Int) -> String {
        switch days {
        case ..<0: return "\(-days) \(dni(-days)) temu"
        case 0: return "dziś"
        case 1: return "jutro"
        default: return "za \(days) dni"
        }
    }

    static func dni(_ n: Int) -> String { n == 1 ? "dzień" : "dni" }

    static func miesiace(_ n: Int) -> String {
        if n == 1 { return "miesiąc" }
        let tens = n % 100, ones = n % 10
        return (2...4).contains(ones) && !(12...14).contains(tens) ? "miesiące" : "miesięcy"
    }

    static func lata(_ n: Int) -> String {
        if n == 1 { return "rok" }
        let tens = n % 100, ones = n % 10
        return (2...4).contains(ones) && !(12...14).contains(tens) ? "lata" : "lat"
    }

    /// Lata, miesiące i dni między dziś a terminem (zawsze dodatnie).
    static func components(to date: Date, from now: Date = .now,
                           calendar: Calendar = .current) -> (years: Int, months: Int, days: Int) {
        let a = calendar.startOfDay(for: now), b = calendar.startOfDay(for: date)
        let c = calendar.dateComponents([.year, .month, .day], from: min(a, b), to: max(a, b))
        return (c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func longParts(to date: Date, from now: Date) -> [String] {
        let c = components(to: date, from: now)
        var parts: [String] = []
        if c.years > 0 { parts.append("\(c.years) \(lata(c.years))") }
        if c.months > 0 { parts.append("\(c.months) \(miesiace(c.months))") }
        if c.days > 0 { parts.append("\(c.days) \(dni(c.days))") }
        return parts
    }

    private static func joined(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " i " + parts[parts.count - 1]
    }

    /// „2 lata, 3 miesiące i 5 dni”.
    static func long(to date: Date, from now: Date = .now) -> String {
        let parts = longParts(to: date, from: now)
        return parts.isEmpty ? "dziś" : joined(parts)
    }

    /// Duży napis + reszta: („2 lata”, „3 miesiące i 5 dni”).
    static func headline(to date: Date, from now: Date = .now) -> (big: String, rest: String?) {
        let parts = longParts(to: date, from: now)
        guard let first = parts.first else { return ("Dziś", nil) }
        let rest = Array(parts.dropFirst())
        return (first, rest.isEmpty ? nil : joined(rest))
    }

    /// Krótko do wiersza: do 60 dni w dniach, dalej „2 l. 3 mies.”.
    static func compact(to date: Date, from now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if abs(days) <= 60 { return short(days) }
        let c = components(to: date, from: now, calendar: calendar)
        var parts: [String] = []
        if c.years > 0 { parts.append("\(c.years) l.") }
        if c.months > 0 { parts.append("\(c.months) mies.") }
        if c.years == 0 && c.days > 0 { parts.append("\(c.days) d.") }
        let text = parts.joined(separator: " ")
        return days < 0 ? text + " po" : text
    }
}

// MARK: - Wygląd

/// Motyw wybrany w ustawieniach (0 = jak w systemie).
enum AppAppearance: Int, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "appearance"
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .system: "Jak w systemie"
        case .light: "Jasny"
        case .dark: "Ciemny"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
