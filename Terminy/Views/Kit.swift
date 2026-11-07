import SwiftUI
import CoreMotion

// MARK: - Zestaw elementów „Midnight”
//
// Prawie czarne tło, gradientowe karty dokumentów, panele i przyciski.
// Wszystkie liczby i kolory pochodzą z `DesignTokens`.

/// Tło aplikacji: głęboka czerń z delikatną poświatą akcentu u góry.
struct AppBackground: View {
    var glow: Color = DT.Palette.accent

    var body: some View {
        ZStack {
            DT.Palette.background
            RadialGradient(colors: [glow.opacity(0.22), .clear],
                           center: .init(x: 0.15, y: -0.05), startRadius: 0, endRadius: DT.Size.hero * 1.6)
            RadialGradient(colors: [DT.Palette.accentAlt.opacity(0.10), .clear],
                           center: .init(x: 1.0, y: 0.1), startRadius: 0, endRadius: DT.Size.hero * 1.2)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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

/// Przechylenie z żyroskopu, wygładzone. Napędza hologram i odblask na kartach.
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
            let money = PL.money(price)
            switch billingCycle ?? .monthly {
            case .monthly: return money + " miesięcznie"
            case .quarterly: return money + " co kwartał"
            case .yearly: return money + " rocznie"
            }
        }
        return [owner, number].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Karta dokumentu

/// Karta dokumentu w stylu karty płatniczej: gradient grupy, złoty chip, hologram i odblask.
struct DocCard: View {
    let data: CardData
    var compact = false
    var tilt = true

    var body: some View {
        let size = compact ? DT.Size.railCard : DT.Size.card
        let expired = data.daysLeft < 0
        let gradient = data.group.gradient
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)

            // Duży znak rodzaju dokumentu jako wzór w tle.
            Image(systemName: data.category.symbol)
                .font(.system(size: size.height * 0.9, weight: .bold))
                .foregroundStyle(DT.Palette.Card.highlight.opacity(0.10))
                .rotationEffect(.degrees(-14))
                .offset(x: size.width * 0.52, y: size.height * 0.18)
                .accessibilityHidden(true)

            RadialGradient(colors: [DT.Palette.Card.highlight.opacity(0.28), .clear],
                           center: .topLeading, startRadius: 0, endRadius: size.width * 0.8)

            Sheen(active: tilt)

            if compact { compactContent } else { fullContent(expired: expired) }
        }
        .foregroundStyle(DT.Palette.Card.ink)
        .frame(width: size.width, height: size.height)
        .saturation(expired ? 0.45 : 1)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                .strokeBorder(LinearGradient(colors: [DT.Palette.Card.highlight.opacity(0.5), DT.Palette.Card.highlight.opacity(0.05)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: DT.Size.hairline)
        }
        .overlay(alignment: .center) {
            if expired && !compact { ExpiredStamp() }
        }
        .shadow(color: gradient[0].opacity(expired ? 0.15 : 0.35), radius: compact ? DT.Space.sm : DT.Space.lg, y: compact ? DT.Space.xs : DT.Space.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(data.title), \(data.category.title)")
        .accessibilityValue(expired ? "po terminie, \(PL.date(data.expiryDate))"
                            : "\(DaysText.sentence(data.daysLeft)), \(PL.date(data.expiryDate))")
    }

    private func fullContent(expired: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DT.Space.xs) {
                Image(systemName: data.category.symbol)
                    .font(DT.Typography.footnoteEmphasized)
                Text(data.category.title.uppercased())
                    .font(DT.Typography.overline)
                    .kerning(DT.Size.hairline)
                    .lineLimit(1)
                Spacer(minLength: DT.Space.xs)
                HoloFoil(active: tilt)
                    .frame(width: DT.Size.hologram.width, height: DT.Size.hologram.height)
            }
            .opacity(0.9)

            CardChip()
                .padding(.top, DT.Space.sm)

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: DT.Space.sm) {
                VStack(alignment: .leading, spacing: DT.Space.xxs) {
                    Text(data.title)
                        .font(DT.Typography.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(data.secondLine.isEmpty ? PL.numeric(data.expiryDate) : data.secondLine)
                        .font(DT.Typography.caption)
                        .opacity(0.8)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                Spacer(minLength: DT.Space.xs)
                let count = data.bigCount
                HStack(alignment: .lastTextBaseline, spacing: DT.Space.xxs) {
                    Text(count.value)
                        .font(count.unit == nil ? DT.Typography.title : DT.Typography.cardNumber)
                        .contentTransition(.numericText(countsDown: true))
                    if let unit = count.unit {
                        Text(unit).font(DT.Typography.footnoteEmphasized).opacity(0.85)
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
        .padding(DT.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: DT.Space.xxs) {
            Image(systemName: data.category.symbol)
                .font(DT.Typography.subheadlineEmphasized)
            Spacer(minLength: 0)
            Text(data.title)
                .font(DT.Typography.subheadlineEmphasized)
                .lineLimit(1)
            Text(DaysText.compact(to: data.expiryDate))
                .font(DT.Typography.caption)
                .monospacedDigit()
                .opacity(0.85)
        }
        .padding(DT.Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Złoty chip jak na karcie płatniczej.
struct CardChip: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DT.Radius.xs + DT.Size.hairline * 2, style: .continuous)
            .fill(LinearGradient(colors: DT.Palette.Card.chip, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: DT.Size.chip.width, height: DT.Size.chip.height)
            .overlay {
                Path { p in
                    let w = DT.Size.chip.width, h = DT.Size.chip.height
                    p.move(to: CGPoint(x: w / 3, y: 0)); p.addLine(to: CGPoint(x: w / 3, y: h))
                    p.move(to: CGPoint(x: w * 2 / 3, y: 0)); p.addLine(to: CGPoint(x: w * 2 / 3, y: h))
                    p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(DT.Palette.Card.lowlight.opacity(0.18), lineWidth: DT.Size.hairline)
            }
            .accessibilityHidden(true)
    }
}

/// Hologram: tęczowa folia, której kolory przesuwają się przy przechylaniu.
struct HoloFoil: View {
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tilt = Tilt.shared
        let angle = active && !reduceMotion ? tilt.x * 160 + tilt.y * 60 : 30
        RoundedRectangle(cornerRadius: DT.Radius.xs, style: .continuous)
            .fill(AngularGradient(colors: DT.Palette.Card.holo, center: .center, angle: .degrees(angle)))
            .opacity(0.85)
            .blendMode(.screen)
            .accessibilityHidden(true)
    }
}

/// Odblask światła przesuwający się po karcie razem z przechyleniem.
struct Sheen: View {
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shift = active && !reduceMotion ? Tilt.shared.x : -0.6
        GeometryReader { geo in
            LinearGradient(colors: [.clear, DT.Palette.Card.highlight.opacity(0.18), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.45)
                .rotationEffect(.degrees(20))
                .offset(x: geo.size.width * (0.3 + shift * 0.55), y: -DT.Space.gutter)
                .frame(height: geo.size.height + DT.Space.gutter * 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Pieczątka „Nieważny”, która spada na kartę po terminie.
struct ExpiredStamp: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        Text("NIEWAŻNY")
            .font(DT.Typography.headline)
            .kerning(DT.Size.hairline * 2)
            .foregroundStyle(DT.Palette.Card.stamp)
            .padding(.horizontal, DT.Space.sm)
            .padding(.vertical, DT.Space.xxs)
            .overlay(Capsule().stroke(DT.Palette.Card.stamp, lineWidth: DT.Size.hairline * 2))
            .background(DT.Palette.dangerFill.opacity(0.85), in: Capsule())
            .rotationEffect(.degrees(-12))
            .scaleEffect(landed || reduceMotion ? 1 : 2.2)
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

// MARK: - Ruch

/// Przycisk-karta: lekko się zapada pod palcem.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(DT.Motion.press, value: configuration.isPressed)
    }
}

/// Wejście elementu: mały podjazd, rozmycie i pojawienie się.
struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : DT.Space.lg)
            .blur(radius: shown || reduceMotion ? 0 : DT.Space.xs)
            .onAppear {
                withAnimation(.spring(duration: 0.6, bounce: 0.15).delay(0.06 + Double(index) * 0.06)) { shown = true }
            }
    }
}

extension View {
    func riseIn(_ index: Int) -> some View { modifier(RiseIn(index: index)) }

    func panel(radius: CGFloat = DT.Radius.panel) -> some View {
        background(DT.Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DT.Palette.separator, lineWidth: DT.Size.hairline))
    }

    func panelCapsule() -> some View {
        background(DT.Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(DT.Palette.separator, lineWidth: DT.Size.hairline))
    }
}

// MARK: - Przyciski

/// Okrągły przycisk z ikoną.
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
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(label)
    }
}

/// Główny przycisk: gradient akcentu z poświatą.
struct PrimaryButton: View {
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
            .background(
                LinearGradient(colors: [DT.Palette.accent, DT.Palette.accent.opacity(0.85)], startPoint: .top, endPoint: .bottom),
                in: Capsule()
            )
            .shadow(color: DT.Palette.accent.opacity(0.45), radius: DT.Space.md, y: DT.Space.xs)
        }
        .buttonStyle(CardPressStyle())
    }
}

/// Okrągła akcja z podpisem (Odnów, Edytuj, Skan…).
struct ActionCircle: View {
    let symbol: String
    let title: String
    var prominent = false
    var tint: Color = DT.Palette.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DT.Space.xs) {
                Image(systemName: symbol)
                    .font(DT.Typography.title3)
                    .foregroundStyle(prominent ? DT.Palette.onAccent : tint)
                    .frame(width: DT.Size.actionCircle, height: DT.Size.actionCircle)
                    .background(prominent ? DT.Palette.accent : DT.Palette.surfaceRaised, in: Circle())
                    .shadow(color: prominent ? DT.Palette.accent.opacity(0.5) : .clear, radius: DT.Space.sm, y: DT.Space.xxs)
                Text(title)
                    .font(DT.Typography.captionEmphasized)
                    .foregroundStyle(DT.Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(CardPressStyle())
    }
}

/// Pigułka filtra.
struct Pill: View {
    let title: String
    var dot: Color?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DT.Space.xs) {
                if let dot { Circle().fill(dot).frame(width: DT.Space.xs, height: DT.Space.xs) }
                Text(title).font(DT.Typography.subheadlineEmphasized).lineLimit(1)
            }
            .foregroundStyle(isOn ? DT.Palette.background : DT.Palette.textPrimary)
            .padding(.horizontal, DT.Space.md)
            .frame(minHeight: DT.Size.pill)
            .background(isOn ? DT.Palette.textPrimary : DT.Palette.surfaceRaised, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(CardPressStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Listy

/// Mała miniatura karty do list.
struct MiniCard: View {
    let category: DocumentCategory

    var body: some View {
        RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
            .fill(LinearGradient(colors: category.group.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: DT.Size.miniCard.width, height: DT.Size.miniCard.height)
            .overlay {
                Image(systemName: category.symbol)
                    .font(DT.Typography.footnoteEmphasized)
                    .foregroundStyle(DT.Palette.Card.ink)
            }
            .accessibilityHidden(true)
    }
}

/// Wiersz dokumentu jak transakcja w aplikacji bankowej: miniatura, nazwa, data, ile zostało.
struct DocRow: View {
    let document: Document

    var body: some View {
        let days = document.daysLeft()
        HStack(spacing: DT.Space.sm) {
            MiniCard(category: document.category)
            VStack(alignment: .leading, spacing: DT.Space.xxs) {
                Text(document.displayTitle)
                    .font(DT.Typography.headline)
                    .foregroundStyle(DT.Palette.textPrimary)
                    .lineLimit(1)
                Text(PL.dayAndMonth(document.expiryDate))
                    .font(DT.Typography.footnote)
                    .foregroundStyle(DT.Palette.textSecondary)
            }
            Spacer(minLength: DT.Space.xs)
            Text(DaysText.compact(to: document.expiryDate))
                .font(DT.Typography.subheadlineEmphasized)
                .monospacedDigit()
                .foregroundStyle(days < 0 ? DT.Palette.danger : days <= 7 ? DT.Palette.warning : DT.Palette.textPrimary)
        }
        .padding(.horizontal, DT.Space.md)
        .frame(minHeight: DT.Size.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Nagłówek sekcji z opcjonalnym przyciskiem po prawej.
struct SectionHeader: View {
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(DT.Typography.title3)
                .foregroundStyle(DT.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(DT.Typography.subheadlineEmphasized)
                    .foregroundStyle(DT.Palette.accentText)
                    .frame(minHeight: DT.Size.touch)
            }
        }
    }
}

/// Pierścień postępu: ile czasu do terminu już minęło.
struct ProgressRing: View {
    let progress: Double
    var color: Color = DT.Palette.onScrim
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: DT.Size.ringLine)
            Circle()
                .trim(from: 0, to: shown ? max(0.02, min(1, progress)) : 0)
                .stroke(color, style: StrokeStyle(lineWidth: DT.Size.ringLine, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: DT.Size.ring, height: DT.Size.ring)
        .onAppear { withAnimation(.spring(duration: 1.2, bounce: 0.1).delay(0.3)) { shown = true } }
        .accessibilityHidden(true)
    }
}

// MARK: - Animowane tło baneru

/// Płynny, żywy gradient w kolorach dokumentu (MeshGradient na iOS 18, obracające się plamy na iOS 17).
struct LiveGradient: View {
    let colors: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            if #available(iOS 18.0, *) {
                AnyView(mesh(t))
            } else {
                AnyView(blobs(t))
            }
        }
    }

    @available(iOS 18.0, *)
    private func mesh(_ t: Double) -> some View {
        let a = colors.first ?? DT.Palette.accent
        let b = colors.last ?? DT.Palette.accentAlt
        let dx = Float(sin(t * 0.6)) * 0.18
        let dy = Float(cos(t * 0.5)) * 0.16
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + dx, 0.5 + dy], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                a, a.opacity(0.9), b,
                b.opacity(0.85), a, DT.Palette.accent,
                DT.Palette.Card.lowlight, b.opacity(0.7), DT.Palette.Card.lowlight,
            ]
        )
    }

    private func blobs(_ t: Double) -> some View {
        let a = colors.first ?? DT.Palette.accent
        let b = colors.last ?? DT.Palette.accentAlt
        return ZStack {
            LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
            AngularGradient(colors: [a, b, DT.Palette.accent, a], center: .center, angle: .degrees(t * 20))
                .blur(radius: DT.Space.xxl)
                .opacity(0.7)
            LinearGradient(colors: [.clear, DT.Palette.Card.lowlight.opacity(0.6)], startPoint: .center, endPoint: .bottom)
        }
    }
}

// MARK: - Iskry po odnowieniu

/// Iskry rozpryskujące się spod karty po odnowieniu. Rysowane w Canvas.
struct RenewBurst: View {
    let trigger: Int
    @State private var start: Date?

    private struct Spark {
        let angle: Double, speed: Double, size: Double, spin: Double, delay: Double, alt: Bool
    }

    private static let sparks: [Spark] = {
        var rng = SeededRandom(seed: 42)
        return (0..<48).map { _ in
            Spark(angle: rng.next() * .pi * 2, speed: 170 + rng.next() * 260, size: 3 + rng.next() * 5,
                  spin: (rng.next() - 0.5) * 12, delay: rng.next() * 0.08, alt: rng.next() > 0.5)
        }
    }()

    private let duration = 0.95

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t < duration else { return }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for spark in Self.sparks {
                    let local = max(0, t - spark.delay)
                    let progress = local / duration
                    let distance = spark.speed * (1 - pow(1 - min(progress, 1), 3)) * 0.9
                    let x = center.x + cos(spark.angle) * distance * 1.25
                    let y = center.y + sin(spark.angle) * distance * 0.8 + 140 * progress * progress
                    let side = spark.size * (1 - progress * 0.5)
                    var piece = context
                    piece.opacity = 1 - progress
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(spark.spin * local))
                    let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side * (spark.alt ? 2.2 : 1))
                    piece.fill(Path(roundedRect: rect, cornerRadius: side / 3),
                               with: .color(spark.alt ? DT.Palette.accentAlt : DT.Palette.onScrim))
                }
            }
        }
        .frame(width: DT.Size.card.width * 3, height: DT.Size.card.width * 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            start = .now
            Task {
                try? await Task.sleep(for: .seconds(duration + 0.1))
                start = nil
            }
        }
    }
}
