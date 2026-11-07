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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(PL.dayAndMonth(.now))
                        .font(.brico(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(W.muted)
                    Text("Portfel")
                        .font(.brico(44, .heavy, relativeTo: .largeTitle))
                        .tracking(-1.5)
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
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(W.muted)
                    TextField("", text: $search, prompt: Text("Nazwa, osoba albo numer").foregroundStyle(W.faint))
                        .font(.brico(17, .medium))
                        .focused($searchFocused)
                        .submitLabel(.search)
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .walletPanel(radius: 23)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if !documents.isEmpty {
                chips
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .background {
            LinearGradient(colors: [W.leatherTop, W.leatherTop.opacity(0.92), W.leatherTop.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private var chips: some View {
        let expired = documents.filter { $0.daysLeft() < 0 }.count
        let soon = documents.filter { (0...30).contains($0.daysLeft()) }.count
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(expired > 0 ? "Wszystkie" : "Wszystkie \(documents.count)", isOn: filter == .all) { filter = .all }
                if expired > 0 {
                    Button { withAnimation(.snappy) { filter = .urgent } } label: {
                        Text(expired == 1 ? "1 po terminie" : "\(expired) po terminie")
                            .font(.brico(14, .bold, relativeTo: .subheadline))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .frame(height: 36)
                            .background(W.alert, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(filter == .urgent ? 0.9 : 0), lineWidth: 2))
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
            HStack(spacing: 7) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(title).font(.brico(14, .bold, relativeTo: .subheadline))
            }
            .foregroundStyle(isOn ? W.goldInk : W.cream)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(isOn ? W.cream : W.surfaceHi, in: Capsule())
        }
        .buttonStyle(CardPressStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Stos kart

    private var cardStack: some View {
        let docs = stack
        return ScrollView {
            VStack(spacing: W.cardPeek - W.cardHeight) {
                ForEach(Array(docs.enumerated()), id: \.element.id) { index, doc in
                    let isFront = index == docs.count - 1
                    Group {
                        if router.opened?.id == doc.id {
                            Color.clear.frame(height: W.cardHeight)
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
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(W.faint)
                        Text(search.isEmpty ? "Nic tu nie pasuje do filtra." : "Brak dokumentów dla „\(search)”.")
                            .font(.brico(17, .medium))
                            .foregroundStyle(W.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }

                if let summary = subscriptionsSummary, search.isEmpty {
                    Text(summary)
                        .font(.brico(14, .medium, relativeTo: .footnote))
                        .foregroundStyle(W.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, W.cardHeight - W.cardPeek + 18)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 196)
            .padding(.bottom, 120)
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
            VStack(alignment: .leading, spacing: 22) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous)
                            .strokeBorder(W.cream.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                            .frame(height: 180)
                            .offset(y: CGFloat(i) * 22)
                            .scaleEffect(1 - CGFloat(2 - i) * 0.05)
                    }
                    VStack(spacing: 6) {
                        Image(systemName: "wallet.pass")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(W.gold)
                            .scaleEffect(breathe && !reduceMotion ? 1.08 : 1)
                        Text("Portfel jest pusty")
                            .font(.brico(22, .heavy, relativeTo: .title2))
                        Text("Włóż pierwszy dokument, a przypomnę o nim miesiąc, tydzień i dzień przed terminem.")
                            .font(.brico(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(W.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 26)
                    }
                    .offset(y: 22)
                }
                .padding(.bottom, 26)
                .riseIn(0)

                if DocumentScanner.isSupported {
                    GoldButton(title: "Zeskanuj dokument", symbol: "doc.viewfinder") { router.add(scan: true) }
                        .riseIn(1)
                }

                WalletSectionTitle(text: "Najczęściej wkładane").riseIn(2)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(common.enumerated()), id: \.element) { index, category in
                        CategoryTile(category: category) { router.add(category) }
                            .riseIn(3 + index)
                    }
                }
                Button { router.add() } label: {
                    Text("Coś innego")
                        .font(.brico(16, .bold))
                        .foregroundStyle(W.cream)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .walletPanel(radius: 16)
                }
                .buttonStyle(CardPressStyle())
                .riseIn(9)
            }
            .padding(.horizontal, 20)
            .padding(.top, 130)
            .padding(.bottom, 120)
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
                    .font(.system(size: 20, weight: .semibold))
                Spacer(minLength: 8)
                Text(category.title)
                    .font(.brico(15, .bold, relativeTo: .subheadline))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(category.group.ink)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(category.group.color)
                    GuillocheShape().stroke(category.group.ink.opacity(0.08), lineWidth: 0.7)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
        }
        .buttonStyle(CardPressStyle())
    }
}
