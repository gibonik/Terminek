import SwiftUI
import SwiftData

/// Filtr nad portfelem.
enum WalletFilter: Hashable {
    case all, urgent, group(CategoryGroup)
}

/// Główny ekran: dokumenty jako karty w portfelu. Z przodu (na dole stosu) leży to, co najpilniejsze.
struct WalletView: View {
    let cards: Namespace.ID

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Document.expiryDate, animation: .snappy) private var documents: [Document]
    @State private var filter: WalletFilter = .all
    @State private var search = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool

    /// Od najdalszego terminu do najbliższego: ostatnia karta jest z przodu i widać ją całą.
    private var stack: [Document] {
        let filtered = documents
            .filter { doc in
                switch filter {
                case .all: true
                case .urgent: doc.daysLeft() <= 30
                case .group(let g): doc.group == g
                }
            }
            .filter { doc in
                search.isEmpty
                    || doc.displayTitle.localizedStandardContains(search)
                    || doc.owner.localizedStandardContains(search)
                    || doc.number.localizedStandardContains(search)
            }
        return Array(filtered.reversed())
    }

    var body: some View {
        ZStack(alignment: .top) {
            if documents.isEmpty {
                EmptyWalletView()
            } else {
                cardStack
            }
            header
        }
        .onAppear {
            Tilt.shared.start()
            router.runLaunchAction(firstDocument: documents.first { $0.daysLeft() >= 0 } ?? documents.first)
        }
        .onDisappear { Tilt.shared.stop() }
    }

    // MARK: Nagłówek

    private var header: some View {
        VStack(alignment: .leading, spacing: DT.Space.md) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: DT.Space.xxs) {
                    Text(PL.dayAndMonth(.now))
                        .font(DT.Typography.subheadline)
                        .foregroundStyle(DT.Palette.textSecondary)
                    Text("Portfel")
                        .font(DT.Typography.largeTitle)
                }
                Spacer()
                if !documents.isEmpty {
                    RoundIconButton(symbol: searching ? "xmark" : "magnifyingglass",
                                    label: searching ? "Zamknij szukanie" : "Szukaj") {
                        withAnimation(.snappy) {
                            searching.toggle()
                            if !searching { search = "" }
                        }
                        searchFocused = searching
                    }
                }
            }

            if searching {
                HStack(spacing: DT.Space.sm) {
                    Image(systemName: "magnifyingglass").foregroundStyle(DT.Palette.textSecondary)
                    TextField("", text: $search, prompt: Text("Nazwa, osoba albo numer").foregroundStyle(DT.Palette.textTertiary))
                        .font(DT.Typography.body)
                        .focused($searchFocused)
                        .submitLabel(.search)
                }
                .padding(.horizontal, DT.Space.md)
                .frame(height: DT.Size.field)
                .walletCapsule()
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if !documents.isEmpty {
                chips
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, DT.Space.lg)
        .padding(.top, DT.Space.xs)
        .padding(.bottom, DT.Space.gutter)
        .background {
            LinearGradient(colors: [DT.Palette.backgroundTop, DT.Palette.backgroundTop.opacity(0.92), DT.Palette.backgroundTop.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private var chips: some View {
        let expired = documents.filter { $0.daysLeft() < 0 }.count
        let soon = documents.filter { (0...30).contains($0.daysLeft()) }.count
        return ScrollView(.horizontal) {
            HStack(spacing: DT.Space.xs) {
                chip(expired > 0 ? "Wszystkie" : "Wszystkie \(documents.count)", isOn: filter == .all) { filter = .all }
                if expired > 0 {
                    Button { withAnimation(.snappy) { filter = .urgent } } label: {
                        Text(expired == 1 ? "1 po terminie" : "\(expired) po terminie")
                            .font(DT.Typography.subheadlineEmphasized)
                            .foregroundStyle(DT.Palette.onDanger)
                            .padding(.horizontal, DT.Space.sm)
                            .frame(height: DT.Size.chip)
                            .background(DT.Palette.dangerFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(DT.Palette.onDanger.opacity(filter == .urgent ? 0.9 : 0), lineWidth: DT.Size.hairline * 2))
                    }
                    .buttonStyle(CardPressStyle())
                }
                if soon > 0 {
                    chip("\(soon) do 30 dni", isOn: filter == .urgent && expired == 0) { filter = .urgent }
                }
                ForEach(CategoryGroup.allCases) { group in
                    let count = documents.filter { $0.group == group }.count
                    if count > 0 {
                        chip(group.title, dot: group.color, isOn: filter == .group(group)) { filter = .group(group) }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func chip(_ title: String, dot: Color? = nil, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            HStack(spacing: DT.Space.xs) {
                if let dot { Circle().fill(dot).frame(width: DT.Space.xs, height: DT.Space.xs) }
                Text(title).font(DT.Typography.subheadlineEmphasized)
            }
            .foregroundStyle(isOn ? DT.Palette.onAccent : DT.Palette.textPrimary)
            .padding(.horizontal, DT.Space.sm)
            .frame(height: DT.Size.chip)
            .background(isOn ? DT.Palette.accent : DT.Palette.surfaceRaised, in: Capsule())
        }
        .buttonStyle(CardPressStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Stos kart

    private var cardStack: some View {
        let docs = stack
        return ScrollView {
            VStack(spacing: DT.Size.cardPeek - DT.Size.cardHeight) {
                ForEach(Array(docs.enumerated()), id: \.element.id) { index, doc in
                    let isFront = index == docs.count - 1
                    Group {
                        if router.opened?.id == doc.id {
                            Color.clear.frame(height: DT.Size.cardHeight)
                        } else {
                            Button { router.open(doc) } label: {
                                DocCard(data: CardData(doc), full: isFront)
                                    .matchedGeometryEffect(id: doc.id, in: cards)
                            }
                            .buttonStyle(CardPressStyle())
                            .contextMenu {
                                Button { router.renew(doc) } label: {
                                    Label("Odnów do \(PL.date(doc.renewedExpiryDate()))", systemImage: "arrow.clockwise")
                                }
                                Button { router.edit(doc) } label: { Label("Edytuj", systemImage: "pencil") }
                                Button(role: .destructive) { delete(doc) } label: { Label("Usuń", systemImage: "trash") }
                            }
                        }
                    }
                    .flyIn(docs.count - 1 - index)
                    .zIndex(Double(index))
                }

                if docs.isEmpty {
                    VStack(spacing: DT.Space.xs) {
                        Image(systemName: "magnifyingglass")
                            .font(DT.Typography.title2)
                            .foregroundStyle(DT.Palette.textTertiary)
                        Text(search.isEmpty ? "Nic tu nie pasuje do filtra." : "Brak dokumentów dla „\(search)”.")
                            .font(DT.Typography.body)
                            .foregroundStyle(DT.Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DT.Space.xxl)
                }

                if let summary = subscriptionsSummary, search.isEmpty {
                    Text(summary)
                        .font(DT.Typography.subheadline)
                        .foregroundStyle(DT.Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, DT.Size.cardHeight - DT.Size.cardPeek + DT.Space.gutter)
                }
            }
            .padding(.horizontal, DT.Space.gutter)
            .padding(.top, DT.Space.xxl)
            .padding(.bottom, DT.Space.dockClearance)
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private var subscriptionsSummary: String? {
        let subs = documents.filter { $0.category == .subscription }
        guard !subs.isEmpty else { return nil }
        let total = subs.reduce(0.0) { $0 + $1.monthlyCost }
        let n = subs.count
        let few = (2...4).contains(n % 10) && !(12...14).contains(n % 100)
        let noun = n == 1 ? "abonament" : (few ? "abonamenty" : "abonamentów")
        let verb = few ? "kosztują" : "kosztuje"
        guard total > 0 else { return nil }
        return "\(n) \(noun) \(verb) razem \(PL.money(total)) miesięcznie"
    }

    private func delete(_ doc: Document) {
        let title = doc.displayTitle
        withAnimation(.snappy) { context.delete(doc) }
        router.show("Wyjęto z portfela „\(title)”", symbol: "trash.circle.fill")
    }
}

// MARK: - Pusty portfel

/// Pierwsze uruchomienie: puste miejsca na karty i najczęstsze dokumenty do włożenia.
struct EmptyWalletView: View {
    @Environment(AppRouter.self) private var router
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let common: [DocumentCategory] = [.carInsurance, .carInspection, .idCard, .drivingLicense, .passport, .subscription]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.lg) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                            .strokeBorder(DT.Palette.textPrimary.opacity(0.22), style: StrokeStyle(lineWidth: DT.Size.hairline * 2, dash: [DT.Space.xs, DT.Space.xs]))
                            .frame(height: DT.Size.emptySlot)
                            .offset(y: CGFloat(i) * DT.Space.lg)
                            .scaleEffect(1 - CGFloat(2 - i) * 0.05)
                    }
                    VStack(spacing: DT.Space.xs) {
                        Image(systemName: "wallet.pass")
                            .font(DT.Typography.title2)
                            .foregroundStyle(DT.Palette.accentText)
                            .scaleEffect(breathe && !reduceMotion ? 1.08 : 1)
                        Text("Portfel jest pusty")
                            .font(DT.Typography.title2)
                        Text("Włóż pierwszy dokument, a przypomnę o nim miesiąc, tydzień i dzień przed terminem.")
                            .font(DT.Typography.subheadline)
                            .foregroundStyle(DT.Palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DT.Space.lg)
                    }
                    .offset(y: DT.Space.lg)
                }
                .padding(.bottom, DT.Space.lg)
                .riseIn(0)

                if DocumentScanner.isSupported {
                    GoldButton(title: "Zeskanuj dokument", symbol: "doc.viewfinder") { router.add(scan: true) }
                        .riseIn(1)
                }

                WalletSectionTitle(text: "Najczęściej wkładane").riseIn(2)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: DT.Space.sm), GridItem(.flexible(), spacing: DT.Space.sm)], spacing: DT.Space.sm) {
                    ForEach(Array(common.enumerated()), id: \.element) { index, category in
                        CategoryTile(category: category) { router.add(category) }
                            .riseIn(3 + index)
                    }
                }
                Button { router.add() } label: {
                    Text("Coś innego")
                        .font(DT.Typography.headline)
                        .foregroundStyle(DT.Palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: DT.Size.row)
                        .walletPanel()
                }
                .buttonStyle(CardPressStyle())
                .riseIn(9)
            }
            .padding(.horizontal, DT.Space.gutter)
            .padding(.top, DT.Space.xxl)
            .padding(.bottom, DT.Space.dockClearance)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

/// Kafelek rodzaju dokumentu: mała karta w kolorze grupy.
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
            .foregroundStyle(category.group.ink)
            .padding(DT.Space.md)
            .frame(maxWidth: .infinity, minHeight: DT.Size.tile, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous).fill(category.group.color)
                    GuillocheShape().stroke(category.group.ink.opacity(0.08), lineWidth: DT.Size.hairline / 2)
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
                }
            }
            .shadow(color: DT.Palette.shadow, radius: DT.Space.sm, y: DT.Space.xs)
        }
        .buttonStyle(CardPressStyle())
    }
}
