import SwiftUI
import CoreMotion

// MARK: - Motyw „Portfel”
//
// Ciemna skóra portfela, kremowy tekst, mosiężne zapięcie jako jedyny akcent.
// Dokumenty to karty w kolorach grup z giloszem i hologramem, który reaguje na przechylenie telefonu.

enum W {
    static let leatherTop = Color(hex: 0x3A2F27)
    static let leather = Color(hex: 0x231C17)
    static let leatherDeep = Color(hex: 0x16110E)
    static let cream = Color(hex: 0xF6EBDD)
    static let muted = Color(hex: 0xF6EBDD).opacity(0.62)
    static let faint = Color(hex: 0xF6EBDD).opacity(0.38)
    static let surface = Color.white.opacity(0.07)
    static let surfaceHi = Color.white.opacity(0.12)
    static let stroke = Color.white.opacity(0.09)
    static let gold = Color(hex: 0xFFD68C)
    static let goldInk = Color(hex: 0x2A1A08)
    static let alert = Color(hex: 0xD93A4C)

    static let cardHeight: CGFloat = 220
    static let cardPeek: CGFloat = 66
    static let cardRadius: CGFloat = 24
}

extension Font {
    /// Bricolage Grotesque z aplikacji, skalowana razem z Dynamic Type.
    static func brico(_ size: CGFloat, _ weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .black, .heavy: name = "BricolageGrotesque-ExtraBold"
        case .bold, .semibold: name = "BricolageGrotesque-Bold"
        default: name = "BricolageGrotesque-Medium"
        }
        return .custom(name, size: size, relativeTo: style)
    }
}

/// Tło: skóra z delikatnym światłem z góry i ziarnem.
struct WalletBackground: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [W.leatherTop, W.leather, W.leatherDeep],
                           center: .init(x: 0.5, y: -0.05), startRadius: 20, endRadius: 760)
            Canvas { context, size in
                var rng = SeededRandom(seed: 7)
                for _ in 0..<1400 {
                    let x = CGFloat(rng.next()) * size.width
                    let y = CGFloat(rng.next()) * size.height
                    let light = rng.next() > 0.5
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)),
                                 with: .color(light ? Color.white.opacity(0.035) : Color.black.opacity(0.12)))
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

// MARK: - Przechylenie telefonu

/// Przechylenie z żyroskopu, wygładzone. Napędza hologram i lekkie pochylenie kart.
@MainActor
@Observable
final class Tilt {
    static let shared = Tilt()
    private(set) var x: Double = 0
    private(set) var y: Double = 0
    private let manager = CMMotionManager()
    private var users = 0

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable, !UIAccessibility.isReduceMotionEnabled else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let tx = max(-1, min(1, motion.attitude.roll / 0.8))
            let ty = max(-1, min(1, (motion.attitude.pitch - 0.7) / 0.8))
            MainActor.assumeIsolated {
                guard let self else { return }
                self.x += (tx - self.x) * 0.18
                self.y += (ty - self.y) * 0.18
            }
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { manager.stopDeviceMotionUpdates() }
    }
}

// MARK: - Dane karty

/// To, co pokazuje karta. Z dokumentu albo na żywo z edytora.
struct CardData: Equatable {
    var category: DocumentCategory
    var title: String
    var owner: String
    var number: String
    var expiryDate: Date
    var price: Double?
    var billingCycle: BillingCycle?

    init(_ document: Document) {
        category = document.category
        title = document.displayTitle
        owner = document.owner
        number = document.number
        expiryDate = document.expiryDate
        price = document.price
        billingCycle = document.billingCycle
    }

    init(category: DocumentCategory, title: String, owner: String, number: String,
         expiryDate: Date, price: Double?, billingCycle: BillingCycle?) {
        self.category = category
        self.title = title.isEmpty ? category.title : title
        self.owner = owner
        self.number = number
        self.expiryDate = expiryDate
        self.price = price
        self.billingCycle = billingCycle
    }

    var group: CategoryGroup { category.group }

    var daysLeft: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: expiryDate)).day ?? 0
    }

    /// Duża liczba i jednostka: („6”, „dni”), („4”, „lata”), („Dziś”, nil).
    var bigCount: (value: String, unit: String?) {
        let d = daysLeft
        if d == 0 { return ("Dziś", nil) }
        if d == 1 { return ("1", "dzień") }
        let a = abs(d)
        if a <= 99 { return ("\(a)", d < 0 ? "dni po" : "dni") }
        let c = DaysText.components(to: expiryDate)
        if c.years > 0 { return ("\(c.years)", DaysText.lata(c.years) + (d < 0 ? " po" : "")) }
        return ("\(c.months)", "mies." + (d < 0 ? " po" : ""))
    }

    var secondLine: String {
        if category == .subscription, let price {
            let cycle = billingCycle ?? .monthly
            let money = PL.money(price)
            switch cycle {
            case .monthly: return money + " miesięcznie"
            case .quarterly: return money + " co kwartał"
            case .yearly: return money + " rocznie"
            }
        }
        return [owner, number].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - Karta dokumentu

struct DocCard: View {
    let data: CardData
    /// Pełna karta (z przodu portfela) albo tylko górny pasek widoczny w stosie.
    var full = true
    var tilt = true

    var body: some View {
        let group = data.group
        let ink = group.ink
        let expired = data.daysLeft < 0
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous)
                .fill(group.color)

            GuillocheShape()
                .stroke(ink.opacity(0.1), lineWidth: 0.8)

            HoloFoil(active: tilt)
                .frame(width: 54, height: 40)
                .padding(.top, 18)
                .padding(.trailing, 18)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Sheen(active: tilt)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Image(systemName: data.category.symbol)
                        .font(.system(size: 13, weight: .semibold))
                    Text(data.category.title)
                        .font(.brico(13, .medium, relativeTo: .caption))
                }
                .opacity(0.72)
                .padding(.trailing, 70)

                Text(data.title)
                    .font(.brico(22, .heavy, relativeTo: .title2))
                    .tracking(-0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.trailing, full ? 70 : 120)

                if full, !data.secondLine.isEmpty {
                    Text(data.secondLine)
                        .font(.brico(15, .medium, relativeTo: .subheadline))
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            if !full {
                Text(DaysText.compact(to: data.expiryDate))
                    .font(.brico(13, .bold, relativeTo: .caption))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(expired ? W.alert : Color.black.opacity(0.13), in: Capsule())
                    .foregroundStyle(expired ? Color.white : ink)
                    .padding(.top, 46)
                    .padding(.trailing, 18)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if full {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(data.category == .subscription ? "Płatność" : "Ważny do")
                            .font(.brico(12, .medium, relativeTo: .caption))
                            .opacity(0.7)
                        Text(PL.numeric(data.expiryDate))
                            .font(.brico(17, .bold, relativeTo: .headline))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    let count = data.bigCount
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(count.value)
                            .font(.brico(count.unit == nil ? 44 : 64, .heavy, relativeTo: .largeTitle))
                            .tracking(-2)
                            .contentTransition(.numericText(countsDown: true))
                        if let unit = count.unit {
                            Text(unit).font(.brico(18, .bold, relativeTo: .headline))
                        }
                    }
                    // Wytłoczenie jak na plastikowej karcie.
                    .shadow(color: .white.opacity(0.35), radius: 0, y: 1)
                    .shadow(color: .black.opacity(0.22), radius: 0, y: -1)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity, alignment: .bottom)

                if expired {
                    ExpiredStamp()
                        .padding(.trailing, 26)
                        .padding(.top, 84)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .foregroundStyle(ink)
        .frame(height: W.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.45), radius: 20, y: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(data.title), \(data.category.title)")
        .accessibilityValue(data.daysLeft < 0 ? "po terminie, \(PL.date(data.expiryDate))"
                            : "\(DaysText.sentence(data.daysLeft)), \(PL.date(data.expiryDate))")
    }
}

/// Hologram: tęczowa folia, której kolory przesuwają się przy przechylaniu.
struct HoloFoil: View {
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tilt = Tilt.shared
        let angle = active && !reduceMotion ? tilt.x * 160 + tilt.y * 60 : 30
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(AngularGradient(
                colors: [Color(hex: 0xFF9AD5), Color(hex: 0x9AE6FF), Color(hex: 0xC4FF9A),
                         Color(hex: 0xFFF19A), Color(hex: 0xFFB59A), Color(hex: 0xFF9AD5)],
                center: .center, angle: .degrees(angle)))
            .overlay {
                // Drobne linie jak w prawdziwym hologramie.
                Canvas { context, size in
                    var x: CGFloat = -size.height
                    while x < size.width {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: size.height))
                        p.addLine(to: CGPoint(x: x + size.height, y: 0))
                        context.stroke(p, with: .color(.white.opacity(0.35)), lineWidth: 0.6)
                        x += 4
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .opacity(0.88)
            .blendMode(.screen)
            .accessibilityHidden(true)
    }
}

/// Odblask światła przesuwający się po karcie razem z przechyleniem.
struct Sheen: View {
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tilt = Tilt.shared
        let shift = active && !reduceMotion ? tilt.x : -0.6
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.22), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.5)
                .rotationEffect(.degrees(20))
                .offset(x: geo.size.width * (0.25 + shift * 0.55), y: -20)
                .frame(height: geo.size.height + 40)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fale jak na banknotach i dowodach.
struct GuillocheShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let amplitude = rect.height * 0.08
        for i in 0..<15 {
            let base = rect.height * (0.14 + 0.05 * CGFloat(i))
            let phase = Double(i) * 0.45
            path.move(to: CGPoint(x: 0, y: base))
            var x: CGFloat = 0
            while x <= rect.width {
                let t = Double(x / rect.width) * .pi * 2.4 + phase
                path.addLine(to: CGPoint(x: x, y: base + CGFloat(sin(t)) * amplitude))
                x += 5
            }
        }
        return path
    }
}

/// Pieczątka „Nieważny”, która spada na kartę po terminie.
struct ExpiredStamp: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        Text("Nieważny")
            .font(.brico(17, .heavy, relativeTo: .headline))
            .foregroundStyle(Color(hex: 0xB3122B))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(hex: 0xB3122B), lineWidth: 2.5)
            }
            .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .rotationEffect(.degrees(-10))
            .scaleEffect(landed || reduceMotion ? 1 : 2)
            .opacity(landed || reduceMotion ? 1 : 0)
            .task {
                guard !landed else { return }
                try? await Task.sleep(for: .milliseconds(420))
                withAnimation(.spring(duration: 0.3, bounce: 0.35)) { landed = true }
                Haptics.shared.fireOnce(.stamp)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Drobne elementy

/// Przycisk-karta: lekko się zapada pod palcem.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

/// Wjazd kart do portfela przy pierwszym pokazaniu.
struct FlyIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: shown || reduceMotion ? 0 : 560 + CGFloat(index) * 30)
            .rotationEffect(.degrees(shown || reduceMotion ? 0 : -5))
            .onAppear {
                withAnimation(.spring(duration: 0.85, bounce: 0.22).delay(Double(index) * 0.06)) { shown = true }
            }
    }
}

/// Wejście elementu: mały podjazd i pojawienie się.
struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.spring(duration: 0.5, bounce: 0.2).delay(0.12 + Double(index) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func flyIn(_ index: Int) -> some View { modifier(FlyIn(index: index)) }
    func riseIn(_ index: Int) -> some View { modifier(RiseIn(index: index)) }

    /// Panel w portfelu: lekko jaśniejsza skóra z cienką krawędzią.
    func walletPanel(radius: CGFloat = 22) -> some View {
        background(W.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(W.stroke, lineWidth: 1))
    }
}

/// Okrągły przycisk na skórze.
struct RoundIconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(W.cream)
                .frame(width: size, height: size)
                .background(W.surfaceHi, in: Circle())
                .overlay(Circle().strokeBorder(W.stroke, lineWidth: 1))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(label)
    }
}

/// Mosiężny przycisk głównej akcji.
struct GoldButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: 17, weight: .bold)) }
                Text(title).font(.brico(17, .bold, relativeTo: .headline))
            }
            .foregroundStyle(W.goldInk)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(W.gold, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: W.gold.opacity(0.25), radius: 14, y: 6)
        }
        .buttonStyle(CardPressStyle())
    }
}

/// Mała miniatura karty do list (kalendarz, przypomnienia).
struct MiniCard: View {
    let category: DocumentCategory

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(category.group.color)
            .frame(width: 46, height: 30)
            .overlay {
                Image(systemName: category.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(category.group.ink)
            }
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// Wiersz dokumentu na skórze: miniatura karty, nazwa, ile zostało.
struct DocRow: View {
    let document: Document

    var body: some View {
        let days = document.daysLeft()
        HStack(spacing: 14) {
            MiniCard(category: document.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.displayTitle)
                    .font(.brico(17, .bold, relativeTo: .body))
                    .foregroundStyle(W.cream)
                    .lineLimit(1)
                Text(PL.dayAndMonth(document.expiryDate))
                    .font(.subheadline)
                    .foregroundStyle(W.muted)
            }
            Spacer(minLength: 8)
            Text(DaysText.compact(to: document.expiryDate))
                .font(.brico(15, .bold, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(days < 0 ? Palette.expired : days <= 7 ? Palette.soon : W.muted)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Nagłówek sekcji na skórze.
struct WalletSectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.brico(20, .bold, relativeTo: .title3))
            .foregroundStyle(W.cream)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .accessibilityAddTraits(.isHeader)
    }
}
