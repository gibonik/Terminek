import SwiftUI
import CoreMotion

// MARK: - Motyw „Portfel”
//
// Skóra portfela (jasna lub ciemna, zależnie od trybu), mosiężne zapięcie jako jedyny akcent.
// Dokumenty to karty w kolorach grup z giloszem i hologramem, który reaguje na przechylenie telefonu.
// Wszystkie liczby i kolory pochodzą z `DesignTokens`.

/// Tło: skóra z delikatnym światłem z góry i ziarnem.
struct WalletBackground: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [DT.Palette.backgroundTop, DT.Palette.background, DT.Palette.backgroundDeep],
                           center: .init(x: 0.5, y: -0.05), startRadius: 20, endRadius: 760)
            Canvas { context, size in
                var rng = SeededRandom(seed: 7)
                for _ in 0..<1400 {
                    let x = CGFloat(rng.next()) * size.width
                    let y = CGFloat(rng.next()) * size.height
                    let light = rng.next() > 0.5
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)),
                                 with: .color(light ? DT.Palette.grainLight : DT.Palette.grainDark))
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
            RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                .fill(group.color)

            GuillocheShape()
                .stroke(ink.opacity(0.1), lineWidth: DT.Size.hairline)

            HoloFoil(active: tilt)
                .frame(width: DT.Size.hologram.width, height: DT.Size.hologram.height)
                .padding(.top, DT.Space.gutter)
                .padding(.trailing, DT.Space.gutter)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Sheen(active: tilt)

            VStack(alignment: .leading, spacing: DT.Space.xxs) {
                HStack(spacing: DT.Space.xs) {
                    Image(systemName: data.category.symbol)
                        .font(DT.Typography.footnoteEmphasized)
                    Text(data.category.title)
                        .font(DT.Typography.footnote)
                }
                .opacity(0.72)
                .padding(.trailing, DT.Space.xxl + DT.Space.lg)

                Text(data.title)
                    .font(DT.Typography.title2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.trailing, full ? DT.Size.hologram.width + DT.Space.md : DT.Space.xxl * 2 + DT.Space.lg)

                if full, !data.secondLine.isEmpty {
                    Text(data.secondLine)
                        .font(DT.Typography.subheadline)
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DT.Space.lg)
            .padding(.top, DT.Space.gutter)

            if !full {
                Text(DaysText.compact(to: data.expiryDate))
                    .font(DT.Typography.footnoteEmphasized)
                    .monospacedDigit()
                    .padding(.horizontal, DT.Space.sm)
                    .padding(.vertical, DT.Space.xxs)
                    .background(expired ? DT.Palette.dangerFill : DT.Palette.Card.lowlight.opacity(0.13), in: Capsule())
                    .foregroundStyle(expired ? DT.Palette.onDanger : ink)
                    .padding(.top, DT.Space.xxl)
                    .padding(.trailing, DT.Space.gutter)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if full {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: DT.Space.xxs) {
                        Text(data.category == .subscription ? "Płatność" : "Ważny do")
                            .font(DT.Typography.caption)
                            .opacity(0.7)
                        Text(PL.numeric(data.expiryDate))
                            .font(DT.Typography.headline)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    let count = data.bigCount
                    HStack(alignment: .lastTextBaseline, spacing: DT.Space.xxs) {
                        Text(count.value)
                            .font(count.unit == nil ? DT.Typography.largeTitle : DT.Typography.display)
                            .contentTransition(.numericText(countsDown: true))
                        if let unit = count.unit {
                            Text(unit).font(DT.Typography.headline)
                        }
                    }
                    // Wytłoczenie jak na plastikowej karcie.
                    .shadow(color: DT.Palette.Card.highlight.opacity(0.35), radius: 0, y: DT.Size.hairline)
                    .shadow(color: DT.Palette.Card.lowlight.opacity(0.22), radius: 0, y: -DT.Size.hairline)
                }
                .padding(.horizontal, DT.Space.lg)
                .padding(.bottom, DT.Space.md)
                .frame(maxHeight: .infinity, alignment: .bottom)

                if expired {
                    ExpiredStamp()
                        .padding(.trailing, DT.Space.lg)
                        .padding(.top, DT.Space.xxl)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .foregroundStyle(ink)
        .frame(height: DT.Size.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [DT.Palette.Card.highlight.opacity(0.45), DT.Palette.Card.highlight.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                    lineWidth: DT.Size.hairline
                )
        }
        .shadow(color: DT.Palette.shadow, radius: DT.Space.gutter, y: DT.Space.md)
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
        RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
            .fill(AngularGradient(
                colors: DT.Palette.Card.holo,
                center: .center, angle: .degrees(angle)))
            .overlay {
                // Drobne linie jak w prawdziwym hologramie.
                Canvas { context, size in
                    var x: CGFloat = -size.height
                    while x < size.width {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: size.height))
                        p.addLine(to: CGPoint(x: x + size.height, y: 0))
                        context.stroke(p, with: .color(DT.Palette.Card.highlight.opacity(0.35)), lineWidth: DT.Size.hairline / 2)
                        x += DT.Space.xxs
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
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
            LinearGradient(colors: [.clear, DT.Palette.Card.highlight.opacity(0.22), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.5)
                .rotationEffect(.degrees(20))
                .offset(x: geo.size.width * (0.25 + shift * 0.55), y: -DT.Space.gutter)
                .frame(height: geo.size.height + DT.Space.gutter * 2)
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
            .font(DT.Typography.headline)
            .foregroundStyle(DT.Palette.Card.stamp)
            .padding(.horizontal, DT.Space.sm)
            .padding(.vertical, DT.Space.xxs)
            .overlay {
                RoundedRectangle(cornerRadius: DT.Radius.xs, style: .continuous)
                    .stroke(DT.Palette.Card.stamp, lineWidth: DT.Size.hairline * 2)
            }
            .background(DT.Palette.Card.highlight.opacity(0.5), in: RoundedRectangle(cornerRadius: DT.Radius.xs, style: .continuous))
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
            .animation(DT.Motion.press, value: configuration.isPressed)
    }
}

/// Wjazd kart do portfela przy pierwszym pokazaniu.
struct FlyIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: shown || reduceMotion ? 0 : DT.Size.cardHeight * 2.5 + CGFloat(index) * DT.Space.xl)
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
            .offset(y: shown || reduceMotion ? 0 : DT.Space.md)
            .onAppear {
                withAnimation(.spring(duration: 0.5, bounce: 0.2).delay(0.12 + Double(index) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func flyIn(_ index: Int) -> some View { modifier(FlyIn(index: index)) }
    func riseIn(_ index: Int) -> some View { modifier(RiseIn(index: index)) }

    /// Panel w portfelu: lekko jaśniejsza skóra z cienką krawędzią.
    func walletPanel(radius: CGFloat = DT.Radius.panel) -> some View {
        background(DT.Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DT.Palette.separator, lineWidth: DT.Size.hairline))
    }

    /// To samo co panel, ale w kształcie pigułki (wyszukiwarka, tagi).
    func walletCapsule() -> some View {
        background(DT.Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(DT.Palette.separator, lineWidth: DT.Size.hairline))
    }
}

/// Okrągły przycisk na skórze.
struct RoundIconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = DT.Size.touch
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(DT.Typography.icon)
                .foregroundStyle(DT.Palette.textPrimary)
                .frame(width: size, height: size)
                .background(DT.Palette.surfaceRaised, in: Circle())
                .overlay(Circle().strokeBorder(DT.Palette.separator, lineWidth: DT.Size.hairline))
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
            HStack(spacing: DT.Space.xs) {
                if let symbol { Image(systemName: symbol).font(DT.Typography.icon) }
                Text(title).font(DT.Typography.headline)
            }
            .foregroundStyle(DT.Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: DT.Size.button)
            .background(DT.Palette.accent, in: RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
            .shadow(color: DT.Palette.accent.opacity(0.25), radius: DT.Space.md, y: DT.Space.xs)
        }
        .buttonStyle(CardPressStyle())
    }
}

/// Mała miniatura karty do list (kalendarz, przypomnienia).
struct MiniCard: View {
    let category: DocumentCategory

    var body: some View {
        RoundedRectangle(cornerRadius: DT.Radius.xs, style: .continuous)
            .fill(category.group.color)
            .frame(width: DT.Size.miniCard.width, height: DT.Size.miniCard.height)
            .overlay {
                Image(systemName: category.symbol)
                    .font(DT.Typography.footnoteEmphasized)
                    .foregroundStyle(category.group.ink)
            }
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.xs, style: .continuous).strokeBorder(DT.Palette.Card.highlight.opacity(0.3), lineWidth: DT.Size.hairline / 2))
            .accessibilityHidden(true)
    }
}

/// Wiersz dokumentu na skórze: miniatura karty, nazwa, ile zostało.
struct DocRow: View {
    let document: Document

    var body: some View {
        let days = document.daysLeft()
        HStack(spacing: DT.Space.md) {
            MiniCard(category: document.category)
            VStack(alignment: .leading, spacing: DT.Space.xxs) {
                Text(document.displayTitle)
                    .font(DT.Typography.headline)
                    .foregroundStyle(DT.Palette.textPrimary)
                    .lineLimit(1)
                Text(PL.dayAndMonth(document.expiryDate))
                    .font(DT.Typography.subheadline)
                    .foregroundStyle(DT.Palette.textSecondary)
            }
            Spacer(minLength: DT.Space.xs)
            Text(DaysText.compact(to: document.expiryDate))
                .font(DT.Typography.subheadlineEmphasized)
                .monospacedDigit()
                .foregroundStyle(days < 0 ? DT.Palette.danger : days <= 7 ? DT.Palette.warning : DT.Palette.textSecondary)
        }
        .padding(.horizontal, DT.Space.md)
        .frame(minHeight: DT.Size.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Nagłówek sekcji na skórze.
struct WalletSectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DT.Typography.title3)
            .foregroundStyle(DT.Palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DT.Space.xs)
            .accessibilityAddTraits(.isHeader)
    }
}
