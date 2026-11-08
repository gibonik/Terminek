import SwiftUI
import SwiftData

/// Start: powitanie, najbliższy termin, pytanie do asystenta, krótkie podsumowanie,
/// to, co wymaga uwagi, i karty. Mało elementów, dużo powietrza.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Document.expiryDate) private var documents: [Document]

    /// Najbliższy dokument, który jeszcze nie minął (a jeśli wszystkie minęły, najświeższy po terminie).
    private var next: Document? {
        documents.first { $0.daysLeft() >= 0 } ?? documents.last
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.lg) {
                header.riseIn(0)

                if let next {
                    HeroBanner(document: next)
                        .zoomSource("hero-\(next.id)")
                        .riseIn(1)
                    AskBar { router.assistantOpen = true }
                        .padding(.horizontal, DT.Space.gutter)
                        .riseIn(2)
                    SummaryStrip(documents: documents)
                        .padding(.horizontal, DT.Space.gutter)
                        .riseIn(2)
                    attention(excluding: next).riseIn(3)
                    carousel.riseIn(4)
                } else {
                    EmptyHome().riseIn(1)
                }
            }
            .padding(.top, DT.Space.xs)
            .padding(.bottom, DT.Space.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            Tilt.shared.start()
            router.runLaunchAction(firstDocument: next)
        }
        .onDisappear { Tilt.shared.stop() }
        .sheet(isPresented: Binding(get: { router.assistantOpen }, set: { router.assistantOpen = $0 })) {
            AssistantView()
                .environment(router)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(DT.Radius.panel + DT.Space.md)
        }
    }

    // MARK: Nagłówek

    /// „Dzień dobry” / „Dobry wieczór” zależnie od pory dnia.
    static func greeting(at date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<18: "Dzień dobry"
        case 18..<23: "Dobry wieczór"
        default: "Dobranoc"
        }
    }

    private var header: some View {
        HStack(spacing: DT.Space.sm) {
            LogoMark(size: DT.Size.iconBadge + DT.Space.xs)

            VStack(alignment: .leading, spacing: 0) {
                Text(PL.dayAndMonth(.now).capitalizedFirst)
                    .font(DT.Typography.footnote)
                    .foregroundStyle(DT.Palette.textSecondary)
                Text(Self.greeting())
                    .font(DT.Typography.title2)
                    .foregroundStyle(DT.Palette.textPrimary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            RoundIconButton(symbol: "sparkles", label: "Asystent") { router.assistantOpen = true }
            RoundIconButton(symbol: "plus", label: "Dodaj dokument") { router.add() }
        }
        .padding(.horizontal, DT.Space.gutter)
    }

    // MARK: Wymaga uwagi / najbliższe

    /// Po terminie i kończące się w 30 dni. Gdy nic nie pali się, po prostu kolejne terminy.
    @ViewBuilder
    private func attention(excluding hero: Document) -> some View {
        let others = documents.filter { $0.id != hero.id }
        let urgent = others.filter { $0.daysLeft() <= 30 }
        let list = Array((urgent.isEmpty ? others.filter { $0.daysLeft() >= 0 } : urgent).prefix(4))
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: DT.Space.sm) {
                SectionHeader(text: urgent.isEmpty ? "Dalej w kolejce" : "Wymaga uwagi", actionTitle: "Kalendarz") {
                    router.tab = .calendar
                }
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, doc in
                        if index > 0 {
                            Rectangle().fill(DT.Palette.separator).frame(height: DT.Size.hairline)
                                .padding(.leading, DT.Space.md * 2 + DT.Size.miniCard.width)
                        }
                        Button { router.open(doc, from: "row-\(doc.id)") } label: { DocRow(document: doc) }
                            .buttonStyle(CardPressStyle())
                            .zoomSource("row-\(doc.id)")
                            .contextMenu { menu(doc) }
                    }
                }
                .panel()
            }
            .padding(.horizontal, DT.Space.gutter)
        }
    }

    // MARK: Karuzela kart

    private var carousel: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            SectionHeader(text: "Twoje karty", actionTitle: "Wszystkie") { router.tab = .wallet }
                .padding(.horizontal, DT.Space.gutter)
            ScrollView(.horizontal) {
                LazyHStack(spacing: DT.Space.md) {
                    ForEach(documents) { doc in
                        Button { router.open(doc, from: "carousel-\(doc.id)") } label: {
                            DocCard(data: CardData(doc))
                        }
                        .buttonStyle(CardPressStyle())
                        .zoomSource("carousel-\(doc.id)")
                        .contextMenu { menu(doc) }
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                                .opacity(phase.isIdentity ? 1 : 0.6)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, DT.Space.lg)
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, DT.Space.gutter, for: .scrollContent)
            .scrollIndicators(.hidden)
            .padding(.vertical, -DT.Space.lg)
        }
    }

    @ViewBuilder
    private func menu(_ doc: Document) -> some View {
        Button { router.renew(doc) } label: {
            Label("Odnów do \(PL.date(doc.renewedExpiryDate()))", systemImage: "arrow.clockwise")
        }
        Button { router.edit(doc) } label: { Label("Edytuj", systemImage: "pencil") }
    }
}

// MARK: - Baner

/// Najbliższy termin: duża liczba dni, data i jedna akcja. Stuknięcie otwiera dokument.
struct HeroBanner: View {
    let document: Document
    @Environment(AppRouter.self) private var router

    var body: some View {
        let days = document.daysLeft()
        let count = CardData(document).bigCount
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack(alignment: .center, spacing: DT.Space.sm) {
                Image(systemName: document.category.symbol)
                    .font(DT.Typography.subheadlineEmphasized)
                    .frame(width: DT.Size.iconBadge, height: DT.Size.iconBadge)
                    .background(DT.Palette.Card.highlight.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(days < 0 ? "PO TERMINIE" : "NAJBLIŻSZY TERMIN")
                        .font(DT.Typography.overline)
                        .kerning(DT.Size.hairline)
                        .opacity(0.8)
                    Text(document.displayTitle)
                        .font(DT.Typography.headline)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                ProgressRing(progress: elapsed)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: DT.Space.xs) {
                Text(count.value)
                    .font(DT.Typography.display)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText(countsDown: true))
                if let unit = count.unit {
                    Text(unit).font(DT.Typography.title3).opacity(0.85)
                }
            }

            HStack(alignment: .center, spacing: DT.Space.sm) {
                Text(days < 0 ? "Termin minął \(PL.dayMonth(document.expiryDate))" : "Ważne do \(PL.date(document.expiryDate))")
                    .font(DT.Typography.subheadline)
                    .opacity(0.85)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Button { router.renew(document) } label: {
                    Label("Odnów", systemImage: "arrow.clockwise")
                        .font(DT.Typography.subheadlineEmphasized)
                        .foregroundStyle(DT.Palette.Card.lowlight)
                        .padding(.horizontal, DT.Space.md)
                        .frame(minHeight: DT.Size.touch)
                        .background(DT.Palette.Card.highlight, in: Capsule())
                }
                .buttonStyle(CardPressStyle())
            }
        }
        .foregroundStyle(DT.Palette.Card.ink)
        .padding(DT.Space.lg)
        .frame(maxWidth: .infinity, minHeight: DT.Size.homeHero, alignment: .topLeading)
        .background {
            LiveGradient(colors: document.category.heroGradient)
                .saturation(days < 0 ? 0.5 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous)
            .strokeBorder(DT.Palette.Card.highlight.opacity(0.15), lineWidth: DT.Size.hairline))
        .shadow(color: document.category.cardGlow.opacity(0.25), radius: DT.Space.lg, y: DT.Space.sm)
        .contentShape(RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous))
        .onTapGesture { router.open(document, from: "hero-\(document.id)") }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Szczegóły") { router.open(document, from: "hero-\(document.id)") }
        .padding(.horizontal, DT.Space.gutter)
    }

    /// Jaka część okresu ważności już minęła (do pierścienia).
    private var elapsed: Double {
        let period = (document.category == .subscription ? document.billingCycle?.components : nil) ?? document.category.defaultRenewal
        let cal = Calendar.current
        guard let start = cal.date(byAdding: DateComponents(year: -(period.year ?? 0), month: -(period.month ?? 0)), to: document.expiryDate) else { return 0 }
        let total = document.expiryDate.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, Date.now.timeIntervalSince(start) / total))
    }
}

// MARK: - Podsumowanie

/// Jeden spokojny pasek z liczbami zamiast rzędu kafelków.
struct SummaryStrip: View {
    let documents: [Document]

    var body: some View {
        let expired = documents.filter { $0.daysLeft() < 0 }.count
        let soon = documents.filter { (0...30).contains($0.daysLeft()) }.count
        let monthly = documents.filter { $0.category == .subscription }.reduce(0.0) { $0 + $1.monthlyCost }
        HStack(spacing: 0) {
            item("\(documents.count)", "w portfelu", DT.Palette.textPrimary)
            divider
            item("\(soon)", "w 30 dni", soon > 0 ? DT.Palette.warning : DT.Palette.textPrimary)
            divider
            item("\(expired)", "po terminie", expired > 0 ? DT.Palette.danger : DT.Palette.textPrimary)
            if monthly > 0 {
                divider
                item(monthly.formatted(.number.precision(.fractionLength(0)).locale(PL.locale)) + " zł", "na miesiąc", DT.Palette.textPrimary)
            }
        }
        .padding(.vertical, DT.Space.md)
        .panel()
    }

    private var divider: some View {
        Rectangle().fill(DT.Palette.separator).frame(width: DT.Size.hairline, height: DT.Space.xl)
    }

    private func item(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: DT.Space.xxs) {
            Text(value)
                .font(DT.Typography.title3)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(label)
                .font(DT.Typography.caption)
                .foregroundStyle(DT.Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pusty start

struct EmptyHome: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            VStack(alignment: .leading, spacing: DT.Space.sm) {
                Image(systemName: "sparkles")
                    .font(DT.Typography.title)
                Spacer(minLength: 0)
                Text("Wszystkie terminy\nw jednym miejscu")
                    .font(DT.Typography.largeTitle)
                Text("Dodaj OC, przegląd, dowód czy abonament. Przypomnę miesiąc, tydzień i dzień przed terminem.")
                    .font(DT.Typography.subheadline)
                    .opacity(0.85)
                HStack(spacing: DT.Space.sm) {
                    if DocumentScanner.isSupported {
                        Button { router.add(scan: true) } label: {
                            Label("Zeskanuj", systemImage: "doc.viewfinder")
                                .font(DT.Typography.subheadlineEmphasized)
                                .foregroundStyle(DT.Palette.Card.lowlight)
                                .padding(.horizontal, DT.Space.md)
                                .frame(minHeight: DT.Size.touch)
                                .background(DT.Palette.Card.highlight, in: Capsule())
                        }
                        .buttonStyle(CardPressStyle())
                    }
                    Button { router.add() } label: {
                        Label("Dodaj ręcznie", systemImage: "plus")
                            .font(DT.Typography.subheadlineEmphasized)
                            .padding(.horizontal, DT.Space.md)
                            .frame(minHeight: DT.Size.touch)
                            .background(DT.Palette.Card.highlight.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(CardPressStyle())
                }
            }
            .foregroundStyle(DT.Palette.Card.ink)
            .padding(DT.Space.gutter)
            .frame(maxWidth: .infinity, minHeight: DT.Size.hero + DT.Space.xxl, alignment: .topLeading)
            .background { LiveGradient(colors: DT.Palette.Card.brand) }
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous))
            .shadow(color: DT.Palette.accent.opacity(0.25), radius: DT.Space.lg, y: DT.Space.sm)

            AddDocumentGrid()
        }
        .padding(.horizontal, DT.Space.gutter)
    }
}

/// Kafelki wszystkich rodzajów dokumentów, które można dodać.
struct AddDocumentGrid: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            SectionHeader(text: "Dodaj dokument", actionTitle: DocumentScanner.isSupported ? "Skanuj" : nil) {
                router.add(scan: true)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DT.Space.sm), GridItem(.flexible(), spacing: DT.Space.sm)],
                      spacing: DT.Space.sm) {
                ForEach(Array(DocumentCategory.allCases.enumerated()), id: \.element) { index, category in
                    CategoryTile(category: category) { router.add(category) }
                        .riseIn(2 + index)
                }
            }
        }
    }
}

/// Kafelek rodzaju dokumentu: mała karta w wyglądzie tego dokumentu.
struct CategoryTile: View {
    let category: DocumentCategory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DT.Space.xxs) {
                HStack {
                    Image(systemName: category.symbol)
                        .font(DT.Typography.title3)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(DT.Typography.headline)
                        .opacity(0.8)
                }
                Spacer(minLength: DT.Space.xs)
                Text(category.cardLabel)
                    .font(DT.Typography.overline)
                    .kerning(DT.Size.hairline)
                    .opacity(0.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(category.title)
                    .font(DT.Typography.subheadlineEmphasized)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(category.cardInk)
            .padding(DT.Space.md)
            .frame(maxWidth: .infinity, minHeight: DT.Size.tile + DT.Space.lg, alignment: .leading)
            .background {
                ZStack {
                    LinearGradient(colors: category.cardGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    CardPattern(category: category, ink: category.cardInk)
                }
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                .strokeBorder(DT.Palette.Card.highlight.opacity(0.25), lineWidth: DT.Size.hairline))
            .shadow(color: category.cardGlow.opacity(0.3), radius: DT.Space.sm, y: DT.Space.xs)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel("Dodaj: \(category.title)")
    }
}

/// Pole „Zapytaj asystenta” na starcie; otwiera czat.
private struct AskBar: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: "sparkles")
                    .font(DT.Typography.headline)
                    .foregroundStyle(LinearGradient(colors: [DT.Palette.accent, DT.Palette.accentAlt],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Zapytaj: kiedy OC? co wygasa w marcu?")
                    .font(DT.Typography.subheadline)
                    .foregroundStyle(DT.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.circle.fill")
                    .font(DT.Typography.title3)
                    .foregroundStyle(DT.Palette.accent)
            }
            .padding(.horizontal, DT.Space.md)
            .frame(minHeight: DT.Size.field)
            .panelCapsule()
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel("Zapytaj asystenta")
    }
}
