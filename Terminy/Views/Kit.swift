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

/// Karta dokumentu. Każdy rodzaj ma własny wygląd: polisa z giloszem, naklejka przeglądu,
/// bordowy paszport z godłem i strefą MRZ, dowód i prawo jazdy ze zdjęciem, ciemna karta subskrypcji.
struct DocCard: View {
    let data: CardData
    var compact = false
    var tilt = true

    private var category: DocumentCategory { data.category }
    private var ink: Color { category.cardInk }

    var body: some View {
        let size = compact ? DT.Size.railCard : DT.Size.card
        let expired = data.daysLeft < 0
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: category.cardGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            CardPattern(category: category, ink: ink)
            RadialGradient(colors: [DT.Palette.Card.highlight.opacity(0.22), .clear],
                           center: .topLeading, startRadius: 0, endRadius: size.width * 0.8)
            Sheen(active: tilt)
            if compact { compactContent } else { fullContent }
        }
        .foregroundStyle(ink)
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
        .shadow(color: category.cardGlow.opacity(expired ? 0.15 : 0.35), radius: compact ? DT.Space.sm : DT.Space.lg, y: compact ? DT.Space.xs : DT.Space.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(data.title), \(data.category.title)")
        .accessibilityValue(expired ? "po terminie, \(PL.date(data.expiryDate))"
                            : "\(DaysText.sentence(data.daysLeft)), \(PL.date(data.expiryDate))")
    }

    // MARK: Pełna karta

    @ViewBuilder
    private var fullContent: some View {
        switch category {
        case .passport: passportLayout
        case .idCard, .drivingLicense: identityLayout
        case .carInspection: inspectionLayout
        case .subscription: subscriptionLayout
        default: policyLayout
        }
    }

    /// Nagłówek: ikona, napis z dokumentu, hologram.
    private var labelRow: some View {
        HStack(spacing: DT.Space.xs) {
            Image(systemName: category.symbol).font(DT.Typography.footnoteEmphasized)
            Text(category.cardLabel)
                .font(DT.Typography.overline)
                .kerning(DT.Size.hairline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: DT.Space.xs)
            HoloFoil(active: tilt)
                .frame(width: DT.Size.hologram.width, height: DT.Size.hologram.height)
        }
        .opacity(0.92)
    }

    private var count: some View {
        let count = data.bigCount
        return HStack(alignment: .lastTextBaseline, spacing: DT.Space.xxs) {
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

    private func titleBlock(_ second: String?) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.xxs) {
            Text(data.title)
                .font(DT.Typography.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(second ?? "Ważne do \(PL.numeric(data.expiryDate))")
                .font(DT.Typography.caption)
                .opacity(0.8)
                .lineLimit(1)
                .monospacedDigit()
        }
    }

    /// Polisy (OC, mieszkanie) i inne: chip, nazwa, ubezpieczyciel, licznik.
    private var policyLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            labelRow
            HStack(spacing: DT.Space.xs) {
                CardChip()
                if !data.number.isEmpty {
                    Text(data.number)
                        .font(DT.Typography.captionEmphasized)
                        .monospaced()
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            .padding(.top, DT.Space.sm)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: DT.Space.sm) {
                titleBlock(data.owner.isEmpty ? nil : data.owner)
                Spacer(minLength: DT.Space.xs)
                count
            }
        }
        .padding(DT.Space.md)
    }

    /// Przegląd: okrągła naklejka z miesiącem i rokiem jak na szybie.
    private var inspectionLayout: some View {
        let cal = Calendar.current
        let month = cal.component(.month, from: data.expiryDate)
        let year = cal.component(.year, from: data.expiryDate)
        return HStack(alignment: .top, spacing: DT.Space.sm) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DT.Space.xs) {
                    Image(systemName: category.symbol).font(DT.Typography.footnoteEmphasized)
                    Text(category.cardLabel)
                        .font(DT.Typography.overline)
                        .kerning(DT.Size.hairline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .opacity(0.92)
                Spacer(minLength: 0)
                titleBlock(data.owner.isEmpty ? nil : data.owner)
                count.padding(.top, DT.Space.xs)
            }
            Spacer(minLength: 0)
            InspectionSticker(month: month, year: year, ink: ink)
        }
        .padding(DT.Space.md)
    }

    /// Paszport: złote godło pośrodku, ramka, strefa MRZ na dole.
    private var passportLayout: some View {
        VStack(spacing: DT.Space.xxs) {
            HStack {
                Text("RZECZPOSPOLITA POLSKA")
                    .font(DT.Typography.overline)
                    .kerning(DT.Size.hairline)
                Spacer()
                count
            }
            Spacer(minLength: 0)
            Image(systemName: "globe.europe.africa.fill")
                .font(DT.Typography.largeTitle)
            Text(category.cardLabel)
                .font(DT.Typography.captionEmphasized)
                .kerning(DT.Size.hairline * 2)
            Spacer(minLength: 0)
            MRZLines(text: mrz, ink: ink)
        }
        .padding(DT.Space.md)
        .overlay {
            RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                .strokeBorder(ink.opacity(0.45), lineWidth: DT.Size.hairline)
                .padding(DT.Space.xs)
        }
    }

    /// Dowód i prawo jazdy: zdjęcie, dane, plakietka UE na prawie jazdy, MRZ na dowodzie.
    private var identityLayout: some View {
        VStack(alignment: .leading, spacing: DT.Space.xs) {
            HStack(spacing: DT.Space.xs) {
                if category == .drivingLicense { EUBadge() }
                VStack(alignment: .leading, spacing: 0) {
                    Text(category.cardLabel)
                        .font(DT.Typography.overline)
                        .kerning(DT.Size.hairline)
                    Text("RZECZPOSPOLITA POLSKA")
                        .font(DT.Typography.caption)
                        .opacity(0.7)
                }
                Spacer(minLength: DT.Space.xs)
                HoloFoil(active: tilt)
                    .frame(width: DT.Size.hologram.width, height: DT.Size.hologram.height)
            }
            HStack(alignment: .bottom, spacing: DT.Space.sm) {
                PhotoBox(ink: ink)
                VStack(alignment: .leading, spacing: DT.Space.xxs) {
                    Text(data.owner.isEmpty ? data.title : data.owner)
                        .font(DT.Typography.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if !data.number.isEmpty {
                        Text(data.number)
                            .font(DT.Typography.captionEmphasized)
                            .monospaced()
                            .lineLimit(1)
                    }
                    if category == .drivingLicense {
                        Text("Kat. B")
                            .font(DT.Typography.captionEmphasized)
                            .padding(.horizontal, DT.Space.xs)
                            .background(ink.opacity(0.12), in: Capsule())
                    }
                    Text("Ważny do \(PL.numeric(data.expiryDate))")
                        .font(DT.Typography.caption)
                        .opacity(0.8)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                count
            }
            if category == .idCard {
                Spacer(minLength: 0)
                MRZLines(text: mrz, ink: ink, lines: 1)
            }
        }
        .padding(DT.Space.md)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Subskrypcja: ciemna karta z neonową poświatą i ceną.
    private var subscriptionLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DT.Space.xs) {
                Image(systemName: "play.rectangle.fill").font(DT.Typography.subheadlineEmphasized)
                    .foregroundStyle(LinearGradient(colors: DT.Palette.Card.subscriptionGlow, startPoint: .leading, endPoint: .trailing))
                Text(category.cardLabel)
                    .font(DT.Typography.overline)
                    .kerning(DT.Size.hairline)
                Spacer()
                Text("Płatność za")
                    .font(DT.Typography.caption)
                    .opacity(0.7)
            }
            Spacer(minLength: 0)
            Text(data.title)
                .font(DT.Typography.title2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .lastTextBaseline) {
                if let price = data.price {
                    Text(PL.money(price))
                        .font(DT.Typography.title3)
                        .foregroundStyle(LinearGradient(colors: DT.Palette.Card.subscriptionGlow, startPoint: .leading, endPoint: .trailing))
                    Text("/ " + (data.billingCycle ?? .monthly).shortTitle)
                        .font(DT.Typography.footnote)
                        .opacity(0.7)
                } else {
                    Text("Następna płatność \(PL.numeric(data.expiryDate))")
                        .font(DT.Typography.footnote)
                        .opacity(0.8)
                }
                Spacer(minLength: DT.Space.xs)
                count
            }
        }
        .padding(DT.Space.md)
    }

    /// Udawana strefa odczytu maszynowego z danych dokumentu.
    private var mrz: String {
        let name = (data.owner.isEmpty ? data.title : data.owner)
            .uppercased()
            .folding(options: .diacriticInsensitive, locale: PL.locale)
            .replacingOccurrences(of: " ", with: "<")
            .filter { $0.isLetter || $0 == "<" }
        let number = data.number.uppercased().filter { $0.isLetter || $0.isNumber }
        let date = PL.numeric(data.expiryDate).filter(\.isNumber)
        return "P<POL\(name)<<<<<<<<<<<<<<<<<<<<\n\(number.isEmpty ? "XX0000000" : number)<POL<\(date)<<<<<<<<"
    }

    // MARK: Mała karta (rzędy)

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: DT.Space.xxs) {
            HStack {
                Image(systemName: category.symbol)
                    .font(DT.Typography.subheadlineEmphasized)
                Spacer()
                if category == .drivingLicense {
                    Text("PL")
                        .font(DT.Typography.overline)
                        .foregroundStyle(DT.Palette.Card.euStar)
                        .padding(.horizontal, DT.Space.xxs)
                        .background(DT.Palette.Card.euBlue, in: RoundedRectangle(cornerRadius: DT.Radius.xs, style: .continuous))
                }
            }
            Spacer(minLength: 0)
            Text(category.cardLabel)
                .font(DT.Typography.overline)
                .opacity(0.75)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

// MARK: - Wzory i elementy kart

/// Tło karty zależne od rodzaju: gilosz na polisach, kropki, wielki znak itd.
struct CardPattern: View {
    let category: DocumentCategory
    let ink: Color

    var body: some View {
        switch category {
        case .carInsurance, .homeInsurance:
            ZStack {
                GuillocheShape().stroke(ink.opacity(0.12), lineWidth: DT.Size.hairline)
                Image(systemName: category == .carInsurance ? "shield.lefthalf.filled" : "house.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(ink.opacity(0.10))
                    .padding(DT.Space.lg)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(x: DT.Space.xl, y: DT.Space.lg)
            }
        case .carInspection:
            Image(systemName: "car.side.fill")
                .resizable().scaledToFit()
                .foregroundStyle(ink.opacity(0.08))
                .padding(.vertical, DT.Space.xl)
                .offset(x: -DT.Space.xl, y: DT.Space.xl)
        case .passport:
            GuillocheShape().stroke(ink.opacity(0.10), lineWidth: DT.Size.hairline / 2)
        case .idCard, .drivingLicense:
            ZStack {
                GuillocheShape().stroke(ink.opacity(0.10), lineWidth: DT.Size.hairline / 2)
                RadialGradient(colors: [DT.Palette.Card.highlight.opacity(0.5), .clear], center: .bottomTrailing,
                               startRadius: 0, endRadius: DT.Size.card.width * 0.7)
            }
        case .subscription:
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: DT.Palette.Card.subscriptionGlow, startPoint: .top, endPoint: .bottom))
                    .frame(width: DT.Size.card.height, height: DT.Size.card.height)
                    .blur(radius: DT.Space.xxl)
                    .offset(x: DT.Size.card.width * 0.45, y: -DT.Space.xl)
                    .opacity(0.7)
                DotGrid().fill(ink.opacity(0.08))
            }
        case .other:
            DotGrid().fill(ink.opacity(0.10))
        }
    }
}

/// Fale jak na banknotach i dokumentach.
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
                x += DT.Space.xxs
            }
        }
        return path
    }
}

/// Siatka kropek.
struct DotGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = DT.Space.md
        var y = step / 2
        while y < rect.height {
            var x = step / 2
            while x < rect.width {
                path.addEllipse(in: CGRect(x: x, y: y, width: DT.Size.hairline * 2, height: DT.Size.hairline * 2))
                x += step
            }
            y += step
        }
        return path
    }
}

/// Okrągła naklejka przeglądu z miesiącem i rokiem.
struct InspectionSticker: View {
    let month: Int
    let year: Int
    let ink: Color

    var body: some View {
        ZStack {
            Circle().fill(DT.Palette.Card.highlight.opacity(0.9))
            Circle().strokeBorder(ink.opacity(0.8), lineWidth: DT.Size.hairline * 2).padding(DT.Space.xxs)
            ForEach(1...12, id: \.self) { m in
                Text("\(m)")
                    .font(DT.Typography.caption)
                    .fontWeight(m == month ? .heavy : .regular)
                    .foregroundStyle(m == month ? DT.Palette.dangerFill : ink.opacity(0.6))
                    .offset(y: -(DT.Size.sticker / 2 - DT.Space.sm))
                    .rotationEffect(.degrees(Double(m) * 30))
            }
            VStack(spacing: 0) {
                Text(String(format: "%02d", month))
                    .font(DT.Typography.title2)
                Text(verbatim: String(year))
                    .font(DT.Typography.captionEmphasized)
            }
            .foregroundStyle(ink)
        }
        .frame(width: DT.Size.sticker, height: DT.Size.sticker)
        .rotationEffect(.degrees(-8))
        .shadow(color: DT.Palette.shadow, radius: DT.Space.xs, y: DT.Space.xxs)
    }
}

/// Miejsce na zdjęcie (sylwetka).
struct PhotoBox: View {
    let ink: Color

    var body: some View {
        RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
            .fill(ink.opacity(0.12))
            .frame(width: DT.Size.photo.width, height: DT.Size.photo.height)
            .overlay(alignment: .bottom) {
                Image(systemName: "person.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(ink.opacity(0.35))
                    .padding(.horizontal, DT.Space.xs)
                    .padding(.top, DT.Space.sm)
            }
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Niebieska plakietka UE z kręgiem gwiazdek i „PL”.
struct EUBadge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DT.Radius.xs, style: .continuous)
            .fill(DT.Palette.Card.euBlue)
            .frame(width: DT.Size.euBadge.width, height: DT.Size.euBadge.height)
            .overlay {
                VStack(spacing: DT.Size.hairline * 2) {
                    ZStack {
                        ForEach(0..<12, id: \.self) { i in
                            Circle().fill(DT.Palette.Card.euStar)
                                .frame(width: DT.Size.hairline * 3, height: DT.Size.hairline * 3)
                                .offset(y: -DT.Space.xs - DT.Size.hairline * 2)
                                .rotationEffect(.degrees(Double(i) * 30))
                        }
                    }
                    .frame(height: DT.Space.lg)
                    Text("PL")
                        .font(DT.Typography.captionEmphasized)
                        .foregroundStyle(DT.Palette.Card.ink)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Strefa MRZ: dwa wiersze „<<<” czcionką o stałej szerokości.
struct MRZLines: View {
    let text: String
    let ink: Color
    var lines = 2

    var body: some View {
        Text(text.split(separator: "\n").prefix(lines).joined(separator: "\n"))
            .font(DT.Typography.caption.monospaced())
            .foregroundStyle(ink.opacity(0.55))
            .lineLimit(lines)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// Znak aplikacji: wachlarz trzech kart i licznik z literą T.
struct LogoMark: View {
    var size: CGFloat = DT.Size.avatar

    var body: some View {
        ZStack {
            card(DT.Palette.Card.carInsurance, angle: 16, dx: -0.1, dy: -0.12)
            card(DT.Palette.Card.homeInsurance, angle: 6, dx: -0.02, dy: -0.04)
            card(DT.Palette.Card.subscriptionGlow, angle: -6, dx: 0.04, dy: 0.06)
                .overlay {
                    ZStack {
                        Circle()
                            .trim(from: 0, to: 0.8)
                            .stroke(DT.Palette.Card.ink, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("T")
                            .font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
                            .foregroundStyle(DT.Palette.Card.ink)
                    }
                    .frame(width: size * 0.36, height: size * 0.36)
                    .rotationEffect(.degrees(-6))
                    .offset(x: size * 0.04, y: size * 0.06)
                }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func card(_ colors: [Color], angle: Double, dx: CGFloat, dy: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size * 0.82, height: size * 0.52)
            .shadow(color: DT.Palette.Card.lowlight.opacity(0.3), radius: size * 0.04, y: size * 0.03)
            .rotationEffect(.degrees(angle))
            .offset(x: size * dx, y: size * dy)
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
            .fill(LinearGradient(colors: category.cardGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: DT.Size.miniCard.width, height: DT.Size.miniCard.height)
            .overlay {
                Image(systemName: category.symbol)
                    .font(DT.Typography.footnoteEmphasized)
                    .foregroundStyle(category.cardInk)
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
