import SwiftUI
import UIKit

// MARK: - Kolory
//
// Aplikacja korzysta z systemowych kolorów (tło, tekst, separatory), więc sama wygląda dobrze
// w jasnym i ciemnym motywie oraz przy zwiększonym kontraście. Własne kolory to tylko
// grupy dokumentów i stany terminu.

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

enum Palette {
    /// Po terminie. Ciemniejsze niż systemowe w jasnym motywie, żeby tekst miał kontrast 4.5:1.
    static let expired = Color(hex: 0xFF6B6B)
    /// Do 7 dni.
    static let soon = Color(hex: 0xFFB25C)
    /// Kolor przewodni: mosiądz zapięcia portfela.
    static let tint = Color(hex: 0xFFD68C)
}

/// Stan terminu do kolorowania tekstu „za ile”.
enum Urgency {
    case expired, soon, later

    init(days: Int) {
        switch days {
        case ..<0: self = .expired
        case 0...7: self = .soon
        default: self = .later
        }
    }

    var color: Color {
        switch self {
        case .expired: Palette.expired
        case .soon: Palette.soon
        case .later: .secondary
        }
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

    /// Kolor karty dokumentu i kropki w kalendarzu.
    var color: Color {
        switch self {
        case .auto: Color(hex: 0xF07A3A)
        case .home: Color(hex: 0x4A90E2)
        case .personal: Color(hex: 0x2BB08C)
        case .subscriptions: Color(hex: 0xF2C230)
        }
    }

    /// Ciemny tekst na karcie w kolorze grupy.
    var ink: Color {
        switch self {
        case .auto: Color(hex: 0x2B1305)
        case .home: Color(hex: 0x061D38)
        case .personal: Color(hex: 0x032A1F)
        case .subscriptions: Color(hex: 0x2E2300)
        }
    }

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

/// Liquid Glass na iOS 26, gdy aplikacja jest budowana nowym Xcode. Starszy Xcode i starszy iOS
/// dostają zwykły wypełniony przycisk.
struct PrimaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
        #else
        content.buttonStyle(.borderedProminent)
        #endif
    }
}

extension View {
    func primaryButton() -> some View { modifier(PrimaryButtonStyle()) }
}

/// Pływający element (komunikat) w Liquid Glass, a na starszym systemie w materiale.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        }
        #else
        content.background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        #endif
    }
}

/// Przejście „zoom” z wiersza do szczegółów (iOS 18+).
struct ZoomSource: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

struct ZoomDestination: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    func glassCapsule() -> some View { modifier(GlassCapsule()) }
    func zoomSource(_ id: UUID, in namespace: Namespace.ID) -> some View { modifier(ZoomSource(id: id, namespace: namespace)) }
    func zoomDestination(_ id: UUID, in namespace: Namespace.ID) -> some View { modifier(ZoomDestination(id: id, namespace: namespace)) }
}
