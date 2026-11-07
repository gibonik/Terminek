import SwiftUI
import SwiftData

/// Start: animowany baner z najbliższym terminem, liczby, karuzela kart, rzędy grup i najbliższe terminy.
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
                    StatsRow(documents: documents).riseIn(2)
                    carousel.riseIn(3)
                    rails
                    upcoming
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
    }

    // MARK: Nagłówek

    private var header: some View {
        HStack(spacing: DT.Space.sm) {
            ZStack {
                Circle().fill(LinearGradient(colors: [DT.Palette.accent, DT.Palette.accentAlt],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "doc.text.fill")
                    .font(DT.Typography.subheadlineEmphasized)
                    .foregroundStyle(DT.Palette.onAccent)
            }
            .frame(width: DT.Size.avatar, height: DT.Size.avatar)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(PL.dayAndMonth(.now))
                    .font(DT.Typography.footnote)
                    .foregroundStyle(DT.Palette.textSecondary)
                Text("Terminy")
                    .font(DT.Typography.title2)
            }
            Spacer()
            RoundIconButton(symbol: "magnifyingglass", label: "Szukaj") {
                router.documentsSearch = true
                router.tab = .wallet
            }
            RoundIconButton(symbol: "bell", label: "Przypomnienia") { router.tab = .account }
        }
        .padding(.horizontal, DT.Space.gutter)
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
                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                .rotation3DEffect(.degrees(phase.value * -14), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
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

    // MARK: Rzędy grup (jak półki w serwisie streamingowym)

    private var rails: some View {
        ForEach(Array(CategoryGroup.allCases.enumerated()), id: \.element) { index, group in
            let docs = documents.filter { $0.group == group }
            if docs.count > 0 {
                VStack(alignment: .leading, spacing: DT.Space.sm) {
                    SectionHeader(text: group.title, actionTitle: "Pokaż") {
                        router.documentsGroup = group
                        router.tab = .wallet
                    }
                    .padding(.horizontal, DT.Space.gutter)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: DT.Space.sm) {
                            ForEach(docs) { doc in
                                Button { router.open(doc, from: "rail-\(doc.id)") } label: {
                                    DocCard(data: CardData(doc), compact: true, tilt: false)
                                }
                                .buttonStyle(CardPressStyle())
                                .zoomSource("rail-\(doc.id)")
                                .contextMenu { menu(doc) }
                                .scrollTransition(.animated, axis: .horizontal) { content, phase in
                                    content.opacity(phase.isIdentity ? 1 : 0.5)
                                        .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                }
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.vertical, DT.Space.md)
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .contentMargins(.horizontal, DT.Space.gutter, for: .scrollContent)
                    .scrollIndicators(.hidden)
                    .padding(.vertical, -DT.Space.md)
                }
                .riseIn(4 + index)
            }
        }
    }

    // MARK: Najbliższe terminy

    private var upcoming: some View {
        let list = Array(documents.filter { $0.daysLeft() >= 0 }.prefix(5))
        return Group {
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: DT.Space.sm) {
                    SectionHeader(text: "Najbliższe terminy", actionTitle: "Kalendarz") { router.tab = .calendar }
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, doc in
                            if index > 0 {
                                Rectangle().fill(DT.Palette.separator).frame(height: DT.Size.hairline)
                                    .padding(.leading, DT.Space.md * 2 + DT.Size.miniCard.width)
                            }
                            Button { router.open(doc, from: "row-\(doc.id)") } label: { DocRow(document: doc) }
                                .buttonStyle(CardPressStyle())
                                .zoomSource("row-\(doc.id)")
                        }
                    }
                    .panel()
                }
                .padding(.horizontal, DT.Space.gutter)
                .riseIn(9)
            }
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

/// Duży animowany baner z odliczaniem do najbliższego terminu.
struct HeroBanner: View {
    let document: Document
    @Environment(AppRouter.self) private var router

    var body: some View {
        let days = document.daysLeft()
        let count = CardData(document).bigCount
        VStack(alignment: .leading, spacing: DT.Space.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DT.Space.xxs) {
                    Text(days < 0 ? "PO TERMINIE" : "NAJBLIŻSZY TERMIN")
                        .font(DT.Typography.overline)
                        .kerning(DT.Size.hairline)
                        .opacity(0.8)
                    Label(document.displayTitle, systemImage: document.category.symbol)
                        .font(DT.Typography.title3)
                        .lineLimit(1)
                }
                Spacer()
                ProgressRing(progress: elapsed)
                    .overlay {
                        Image(systemName: document.category.symbol)
                            .font(DT.Typography.footnoteEmphasized)
                    }
            }

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: DT.Space.xs) {
                Text(count.value)
                    .font(DT.Typography.display)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText(countsDown: true))
                if let unit = count.unit {
                    Text(unit).font(DT.Typography.title2).opacity(0.85)
                }
            }
            Text(days < 0 ? "Termin minął \(PL.dayMonth(document.expiryDate))" : "Ważne do \(PL.date(document.expiryDate))")
                .font(DT.Typography.subheadline)
                .opacity(0.85)

            HStack(spacing: DT.Space.sm) {
                Button { router.renew(document) } label: {
                    Label("Odnów", systemImage: "arrow.clockwise")
                        .font(DT.Typography.subheadlineEmphasized)
                        .foregroundStyle(DT.Palette.Card.lowlight)
                        .padding(.horizontal, DT.Space.md)
                        .frame(minHeight: DT.Size.touch)
                        .background(DT.Palette.Card.highlight, in: Capsule())
                }
                .buttonStyle(CardPressStyle())
                Button { router.open(document, from: "hero-\(document.id)") } label: {
                    Label("Szczegóły", systemImage: "arrow.up.right")
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
        .frame(maxWidth: .infinity, minHeight: DT.Size.hero, alignment: .topLeading)
        .background {
            LiveGradient(colors: document.group.gradient)
                .saturation(days < 0 ? 0.5 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous)
            .strokeBorder(DT.Palette.Card.highlight.opacity(0.15), lineWidth: DT.Size.hairline))
        .shadow(color: document.group.color.opacity(0.4), radius: DT.Space.xl, y: DT.Space.md)
        .padding(.horizontal, DT.Space.gutter)
        .scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                .opacity(phase.isIdentity ? 1 : 0.7)
        }
        .accessibilityElement(children: .contain)
    }

    /// Jaka część okresu ważności już minęła (do pierścienia).
    private var elapsed: Double {
        let period = document.category.defaultRenewal
        let cal = Calendar.current
        guard let start = cal.date(byAdding: DateComponents(year: -(period.year ?? 0), month: -(period.month ?? 0)), to: document.expiryDate) else { return 0 }
        let total = document.expiryDate.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, Date.now.timeIntervalSince(start) / total))
    }
}

// MARK: - Liczby

struct StatsRow: View {
    let documents: [Document]

    var body: some View {
        let expired = documents.filter { $0.daysLeft() < 0 }.count
        let soon = documents.filter { (0...30).contains($0.daysLeft()) }.count
        let monthly = documents.filter { $0.category == .subscription }.reduce(0.0) { $0 + $1.monthlyCost }
        ScrollView(.horizontal) {
            HStack(spacing: DT.Space.sm) {
                StatTile(value: Double(documents.count), label: "w portfelu", symbol: "rectangle.stack.fill", tint: DT.Palette.accentText)
                StatTile(value: Double(soon), label: "w 30 dni", symbol: "clock.fill", tint: DT.Palette.warning)
                StatTile(value: Double(expired), label: "po terminie", symbol: "exclamationmark.circle.fill", tint: DT.Palette.danger)
                if monthly > 0 {
                    StatTile(value: monthly, label: "zł / mies. abonamenty", symbol: "creditcard.fill", tint: DT.Palette.success, money: true)
                }
            }
        }
        .contentMargins(.horizontal, DT.Space.gutter, for: .scrollContent)
        .scrollIndicators(.hidden)
    }
}

struct StatTile: View {
    let value: Double
    let label: String
    let symbol: String
    let tint: Color
    var money = false
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.xs) {
            Image(systemName: symbol)
                .font(DT.Typography.subheadlineEmphasized)
                .foregroundStyle(tint)
                .frame(width: DT.Size.iconBadge, height: DT.Size.iconBadge)
                .background(tint.opacity(0.14), in: Circle())
            Text(money ? (shown ? value : 0).formatted(.number.precision(.fractionLength(0)).locale(PL.locale)) : "\(Int(shown ? value : 0))")
                .font(DT.Typography.title)
                .monospacedDigit()
                .contentTransition(.numericText(value: shown ? value : 0))
            Text(label)
                .font(DT.Typography.footnote)
                .foregroundStyle(DT.Palette.textSecondary)
                .lineLimit(1)
        }
        .padding(DT.Space.md)
        .frame(minWidth: DT.Size.tile * 1.25, alignment: .leading)
        .panel()
        .onAppear { withAnimation(.spring(duration: 0.9, bounce: 0.1).delay(0.25)) { shown = true } }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pusty start

struct EmptyHome: View {
    @Environment(AppRouter.self) private var router
    private let common: [DocumentCategory] = [.carInsurance, .carInspection, .idCard, .drivingLicense, .passport, .subscription]

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
            .background { LiveGradient(colors: [DT.Palette.accent, DT.Palette.accentAlt]) }
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.panel, style: .continuous))
            .shadow(color: DT.Palette.accent.opacity(0.4), radius: DT.Space.xl, y: DT.Space.md)

            SectionHeader(text: "Najczęściej dodawane")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DT.Space.sm), GridItem(.flexible(), spacing: DT.Space.sm)],
                      spacing: DT.Space.sm) {
                ForEach(Array(common.enumerated()), id: \.element) { index, category in
                    CategoryTile(category: category) { router.add(category) }
                        .riseIn(2 + index)
                }
            }
        }
        .padding(.horizontal, DT.Space.gutter)
    }
}

/// Kafelek rodzaju dokumentu w gradiencie grupy.
struct CategoryTile: View {
    let category: DocumentCategory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: category.symbol)
                    .font(DT.Typography.title3)
                Spacer(minLength: DT.Space.xs)
                Text(category.title)
                    .font(DT.Typography.subheadlineEmphasized)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(DT.Palette.Card.ink)
            .padding(DT.Space.md)
            .frame(maxWidth: .infinity, minHeight: DT.Size.tile, alignment: .leading)
            .background(LinearGradient(colors: category.group.gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
            .shadow(color: category.group.color.opacity(0.3), radius: DT.Space.sm, y: DT.Space.xs)
        }
        .buttonStyle(CardPressStyle())
    }
}
