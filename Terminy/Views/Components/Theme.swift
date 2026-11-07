import SwiftUI
import UIKit

// MARK: - Kolory

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: alpha))
    }

    /// Kolor, który sam zmienia się między jasnym a ciemnym motywem.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// Paleta z zaakceptowanego projektu (jasny / ciemny).
enum Palette {
    static let bg = Color.dynamic(0xEDEFF5, 0x0D0F15)
    static let ink = Color.dynamic(0x14161F, 0xF3F4F8)
    static let muted = Color.dynamic(0x5E6372, 0x9498A6)
    static let panel = Color.dynamic(0xFFFFFF, 0x171A23)
    static let tile = Color.dynamic(0xF2F3F8, 0x212532)
    static let line = Color.dynamic(0xE3E5EE, 0x2C3140)

    static let nav = Color.dynamic(0x14161F, 0xF3F4F8)
    static let navOn = Color.dynamic(0xFFFFFF, 0x0D0F15)
    static let navOff = Color.dynamic(0x868B9A, 0x6B7080)
    static let navOnBg = Color.dynamic(0x2A2E3B, 0xDDE0EA)

    /// Po terminie.
    static let alert = Color(hex: 0xF2557A)
    static let alertInk = Color(hex: 0x8A1230)
    /// Przycisk „+”.
    static let accent = Color(hex: 0xFF7A45)
    static let accentInk = Color(hex: 0x2A1203)
    static let switchOn = Color(hex: 0x2EC4A0)
    static let urgentChip = Color(hex: 0x14161F)
}

/// Polskie nazwy i daty niezależnie od języka telefonu (cała appka jest po polsku).
enum PL {
    static let locale = Locale(identifier: "pl_PL")
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        cal.firstWeekday = 2
        return cal
    }

    static let months = ["Styczeń", "Luty", "Marzec", "Kwiecień", "Maj", "Czerwiec",
                         "Lipiec", "Sierpień", "Wrzesień", "Październik", "Listopad", "Grudzień"]
    static let monthsShort = ["STY", "LUT", "MAR", "KWI", "MAJ", "CZE", "LIP", "SIE", "WRZ", "PAŹ", "LIS", "GRU"]
    static let weekdays = ["Pn", "Wt", "Śr", "Cz", "Pt", "So", "Nd"]

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }

    /// „Sobota, 7 listopada”.
    static func today(_ date: Date = .now) -> String {
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func money(_ value: Double) -> String {
        let rounded = value.rounded()
        let digits = abs(value - rounded) < 0.005 ? 0 : 2
        return value.formatted(.number.precision(.fractionLength(digits)).locale(locale)) + " zł"
    }
}

// MARK: - Grupy kategorii (kolory kart)

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

    var color: Color {
        switch self {
        case .auto: Color(hex: 0xFF7A45)
        case .home: Color(hex: 0x4BA3FF)
        case .personal: Color(hex: 0x2EC4A0)
        case .subscriptions: Color(hex: 0xFFC53D)
        }
    }

    /// Ciemny kolor tekstu na karcie w kolorze grupy.
    var ink: Color {
        switch self {
        case .auto: Color(hex: 0x2A1203)
        case .home: Color(hex: 0x04223F)
        case .personal: Color(hex: 0x03291F)
        case .subscriptions: Color(hex: 0x2B1F00)
        }
    }

    var symbol: String {
        switch self {
        case .auto: "car.fill"
        case .home: "house.fill"
        case .personal: "person.text.rectangle.fill"
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
}

extension Document {
    var group: CategoryGroup { category.group }

    /// Koszt miesięczny subskrypcji (do kafla na pulpicie).
    var monthlyCost: Double {
        guard category == .subscription, let price else { return 0 }
        switch billingCycle ?? .monthly {
        case .monthly: return price
        case .quarterly: return price / 3
        case .yearly: return price / 12
        }
    }

    /// Druga linijka na karcie: osoba, numer albo cena.
    var cardSubtitle: String {
        var parts: [String] = []
        if category == .subscription, let price {
            parts.append(PL.money(price) + " / " + (billingCycle ?? .monthly).shortTitle)
        }
        if !owner.isEmpty { parts.append(owner) }
        if !number.isEmpty, parts.count < 2 { parts.append(number) }
        if parts.isEmpty { parts.append(category.title) }
        return parts.joined(separator: " · ")
    }
}

extension BillingCycle {
    var shortTitle: String {
        switch self {
        case .monthly: "mies."
        case .quarterly: "kw."
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

    /// Liczba i jednostka osobno, do dużego licznika w pierścieniu.
    static func split(_ days: Int) -> (value: String, unit: String) {
        let a = abs(days)
        if a <= 365 { return ("\(a)", a == 1 ? "DZIEŃ" : "DNI") }
        let years = a / 365
        return ("\(years)", lata(years).uppercased())
    }

    static func dni(_ n: Int) -> String { n == 1 ? "dzień" : "dni" }

    static func miesiace(_ n: Int) -> String {
        if n == 1 { return "miesiąc" }
        let tens = n % 100, ones = n % 10
        return (2...4).contains(ones) && !(12...14).contains(tens) ? "miesiące" : "miesięcy"
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

    /// Krótko na plakietkę: do 60 dni w dniach, dalej „2 l. 3 mies.”.
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

    static func lata(_ n: Int) -> String {
        if n == 1 { return "rok" }
        let tens = n % 100, ones = n % 10
        return (2...4).contains(ones) && !(12...14).contains(tens) ? "lata" : "lat"
    }
}

// MARK: - Małe elementy

/// Plakietka z liczbą dni. Czerwona po terminie, czarna do 7 dni.
struct DaysChip: View {
    let days: Int
    let text: String
    /// Kolor tekstu, gdy plakietka leży na kolorowej karcie. `nil` = na zwykłym panelu.
    var onCardInk: Color?
    var size: CGFloat = 11

    init(document: Document, onCardInk: Color? = nil, size: CGFloat = 11) {
        self.days = document.daysLeft()
        self.text = DaysText.compact(to: document.expiryDate)
        self.onCardInk = onCardInk
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy).monospacedDigit())
            .lineLimit(1)
            .padding(.horizontal, size * 0.7)
            .padding(.vertical, size * 0.3)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
            .contentTransition(.numericText())
    }

    private var background: Color {
        if days < 0 { return Palette.alert }
        if days <= 7 { return Palette.urgentChip }
        return onCardInk == nil ? Palette.tile : Color.black.opacity(0.12)
    }

    private var foreground: Color {
        if days <= 7 { return .white }
        return onCardInk ?? Palette.ink
    }
}

/// Pierścień: ile z ostatnich 30 dni przed terminem już minęło.
struct CountdownRing: View {
    let daysLeft: Int
    var color: Color
    var lineWidth: CGFloat = 9
    @State private var shown: Double = 0

    private var progress: Double {
        if daysLeft <= 0 { return 1 }
        return 1 - min(Double(daysLeft), 30) / 30
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            withAnimation(.spring(duration: 1.2, bounce: 0.3).delay(0.2)) { shown = progress }
        }
        .onChange(of: daysLeft) {
            withAnimation(.spring(duration: 0.8, bounce: 0.3)) { shown = progress }
        }
    }
}

/// Lekkie „wciśnięcie” przycisków.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// Wjazd elementu od dołu przy pierwszym pokazaniu, z opóźnieniem dla efektu kaskady.
struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear {
                withAnimation(.spring(duration: 0.55, bounce: 0.25).delay(Double(index) * 0.06)) { shown = true }
            }
    }
}

extension View {
    func riseIn(_ index: Int) -> some View { modifier(RiseIn(index: index)) }

    /// Miejsce na pływający pasek, żeby nie zasłaniał ostatnich wierszy.
    func tabBarClearance() -> some View {
        contentMargins(.bottom, 110, for: .scrollContent)
    }

    func screenTitle() -> some View {
        font(.system(size: 30, weight: .heavy)).tracking(-0.9)
    }
}

/// Duży tytuł ekranu po lewej stronie.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                if let subtitle {
                    Text(subtitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.muted)
                }
                Text(title).screenTitle()
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Okrągły przycisk w nagłówku.
struct CircleIconButton: View {
    let symbol: String
    let label: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.panel, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Palette.alert, in: Capsule())
                            .offset(x: -4, y: 4)
                    }
                }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

/// Pigułka filtra z kolorową kropką i licznikiem.
struct FilterPill: View {
    let title: String
    let dot: Color
    let count: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(dot)
                    .frame(width: 10, height: 10)
                Text(title).font(.system(size: 14, weight: .bold))
                Text("\(count)").font(.system(size: 12, weight: .heavy)).opacity(0.6)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .frame(height: 38)
            .background(isOn ? Palette.ink : Palette.panel, in: Capsule())
            .foregroundStyle(isOn ? Palette.bg : Palette.ink)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
