import SwiftUI
import SwiftData

/// Pulpit według szkicu: panel z dwoma kaflami u góry, filtry, dwie talie kart.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Document.expiryDate) private var documents: [Document]

    @State private var filter: CategoryGroup?
    @State private var openStack: String?
    @State private var renewTick = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header.riseIn(0)

                if documents.isEmpty {
                    EmptyHome().riseIn(1)
                } else {
                    if let expired = documents.first(where: { $0.daysLeft() < 0 }) {
                        ExpiredBanner(document: expired) { renew(expired) }
                            .riseIn(1)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    topPanel.riseIn(2)
                    filterRow.riseIn(3)
                    stacks.riseIn(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .tabBarClearance()
        .background(Palette.bg.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: renewTick)
    }

    // MARK: Nagłówek

    private var urgentCount: Int { documents.filter { $0.daysLeft() <= 7 }.count }

    private var header: some View {
        ScreenHeader(title: "Terminy", subtitle: PL.today()) {
            HStack(spacing: 8) {
                CircleIconButton(symbol: "magnifyingglass", label: "Szukaj") {
                    router.openList(.all, search: true)
                }
                CircleIconButton(symbol: "bell.fill", label: "Pilne: \(urgentCount)", badge: urgentCount) {
                    router.openList(.urgent)
                }
            }
        }
    }

    // MARK: Panel z dwoma kaflami

    private var hero: Document? {
        documents.first(where: { $0.daysLeft() >= 0 }) ?? documents.first
    }

    private var topPanel: some View {
        HStack(spacing: 10) {
            if let hero {
                HeroTile(document: hero, onOpen: { router.selected = hero }, onRenew: { renew(hero) })
            }
            SoonTile(documents: documents, onOpen: { router.selected = $0 })
        }
        .frame(height: 214)
        .padding(10)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Color(hex: 0x14161F).opacity(0.07), radius: 15, y: 10)
    }

    // MARK: Filtry

    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterPill(title: "Wszystko", dot: filter == nil ? Palette.bg : Palette.ink,
                           count: documents.count, isOn: filter == nil) { pick(nil) }
                ForEach(CategoryGroup.allCases) { group in
                    FilterPill(title: group.title, dot: group.color,
                               count: documents.filter { $0.group == group }.count,
                               isOn: filter == group) { pick(group) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func pick(_ group: CategoryGroup?) {
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) {
            filter = group
            openStack = nil
        }
    }

    // MARK: Talie kart

    private struct StackGroup: Identifiable {
        let id: String
        let title: String
        let docs: [Document]
        let addCategory: DocumentCategory
    }

    private var groups: [StackGroup] {
        if let filter {
            return [StackGroup(id: filter.rawValue, title: filter.title,
                               docs: documents.filter { $0.group == filter },
                               addCategory: filter.categories.first ?? .other)]
        }
        return [
            StackGroup(id: "auto", title: "Auto",
                       docs: documents.filter { $0.group == .auto }, addCategory: .carInsurance),
            StackGroup(id: "rest", title: "Dom i osobiste",
                       docs: documents.filter { $0.group == .home || $0.group == .personal }, addCategory: .idCard),
        ]
    }

    private var stacks: some View {
        let groups = groups
        let single = groups.count == 1
        return HStack(alignment: .top, spacing: 10) {
            ForEach(groups) { group in
                CardStack(
                    title: group.title,
                    documents: group.docs,
                    isOpen: single || openStack == group.id,
                    showsToggle: !single,
                    onToggle: {
                        withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                            openStack = openStack == group.id ? nil : group.id
                        }
                    },
                    onOpen: { router.selected = $0 },
                    onAdd: { router.add(group.addCategory) }
                )
            }
        }
    }

    private func renew(_ document: Document) {
        withAnimation(.spring(duration: 0.6, bounce: 0.3)) { document.renew() }
        renewTick += 1
    }
}

// MARK: - Pasek „wygasło”

private struct ExpiredBanner: View {
    let document: Document
    let onRenew: () -> Void
    @State private var pulse = false

    var body: some View {
        let days = -document.daysLeft()
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.white.opacity(0.5))
                    .frame(width: 10, height: 10)
                    .scaleEffect(pulse ? 2.4 : 1)
                    .opacity(pulse ? 0 : 1)
                Circle().fill(.white).frame(width: 10, height: 10)
            }
            .frame(width: 14)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("\(document.displayTitle) – po terminie")
                    .font(.system(size: 14, weight: .heavy))
                    .lineLimit(1)
                Text("Termin minął \(days) \(DaysText.dni(days)) temu")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.9)
            }
            Spacer(minLength: 4)
            Button(action: onRenew) {
                Text("Odnów")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Palette.alertInk)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
        }
        .foregroundStyle(.white)
        .padding(.vertical, 10)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .background(Palette.alert, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Kafel „najbliżej”

private struct HeroTile: View {
    let document: Document
    let onOpen: () -> Void
    let onRenew: () -> Void

    var body: some View {
        let days = document.daysLeft()
        let split = DaysText.split(days)
        let group = document.group

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(days < 0 ? "PO TERMINIE" : "NAJBLIŻEJ")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6).opacity(0.8)
                Spacer(minLength: 4)
                Text(group.title)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 6)
            ZStack {
                CountdownRing(daysLeft: days, color: group.ink)
                VStack(spacing: 0) {
                    Text(split.value)
                        .font(.system(size: 24, weight: .heavy).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(split.unit).font(.system(size: 10, weight: .bold)).opacity(0.8)
                }
            }
            .frame(width: 80, height: 80)
            Spacer(minLength: 6)
            Text(document.displayTitle)
                .font(.system(size: 16, weight: .heavy)).tracking(-0.3)
                .lineLimit(1)
            Text(document.cardSubtitle)
                .font(.system(size: 12, weight: .semibold)).opacity(0.75)
                .lineLimit(1)
                .padding(.bottom, 8)
            Button(action: onRenew) {
                Label("Odnowione", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(group.ink, in: Capsule())
                    .foregroundStyle(group.color)
            }
            .buttonStyle(PressScaleStyle())
        }
        .foregroundStyle(group.ink)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(group.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onOpen)
        .id(document.id)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

// MARK: - Kafel „na 30 dni”

private struct SoonTile: View {
    let documents: [Document]
    let onOpen: (Document) -> Void

    var body: some View {
        let soon = Array(documents.filter { $0.daysLeft() <= 30 }.prefix(4))
        let monthly = documents.reduce(0.0) { $0 + $1.monthlyCost }

        VStack(alignment: .leading, spacing: 0) {
            Text("NA 30 DNI")
                .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Palette.muted)
            Spacer(minLength: 8)
            if soon.isEmpty {
                Text("Spokój. Nic nie wygasa w tym miesiącu.")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.muted)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(soon) { doc in
                        Button { onOpen(doc) } label: {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3).fill(doc.group.color).frame(width: 8, height: 8)
                                Text(doc.displayTitle)
                                    .font(.system(size: 13, weight: .bold))
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                let d = doc.daysLeft()
                                Text(d < 0 ? "po" : "\(d) d")
                                    .font(.system(size: 12, weight: .heavy).monospacedDigit())
                                    .foregroundStyle(d < 0 ? Palette.alert : Palette.ink)
                            }
                            .foregroundStyle(Palette.ink)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 8)
            Divider().overlay(Palette.line)
            VStack(alignment: .leading, spacing: 0) {
                Text(PL.money(monthly.rounded()))
                    .font(.system(size: 22, weight: .heavy)).tracking(-0.6)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text("abonamenty / mies.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.top, 10)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.tile, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Talia kart

struct CardStack: View {
    let title: String
    let documents: [Document]
    let isOpen: Bool
    let showsToggle: Bool
    let onToggle: () -> Void
    let onOpen: (Document) -> Void
    let onAdd: () -> Void

    private let cardHeight: CGFloat = 100

    var body: some View {
        // Na wierzchu (na dole talii) leży najpilniejszy dokument.
        let items = Array(documents.reversed())
        let step: CGFloat = isOpen ? 108 : 28
        let height = step * CGFloat(max(items.count - 1, 0)) + cardHeight

        VStack(alignment: .leading, spacing: 8) {
            Button(action: showsToggle ? onToggle : {}) {
                HStack {
                    Text(title).font(.system(size: 16, weight: .heavy)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(hint(count: items.count))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.muted)
                    if showsToggle && !items.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Palette.muted)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(items.isEmpty)

            if items.isEmpty {
                Button(action: onAdd) {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .heavy))
                        Text("Dodaj").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: cardHeight)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    }
                }
                .buttonStyle(PressScaleStyle())
            } else {
                ZStack(alignment: .top) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, doc in
                        let fromFront = items.count - 1 - index
                        StackCard(document: doc)
                            .frame(height: cardHeight)
                            .scaleEffect(isOpen ? 1 : 1 - CGFloat(fromFront) * 0.04, anchor: .top)
                            .offset(y: CGFloat(index) * step)
                            .zIndex(Double(index))
                            .onTapGesture {
                                if isOpen || fromFront == 0 || !showsToggle { onOpen(doc) } else { onToggle() }
                            }
                    }
                }
                .frame(height: height, alignment: .top)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func hint(count: Int) -> String {
        if !showsToggle { return "\(count) dok." }
        if count == 0 { return "" }
        return isOpen ? "zwiń" : "\(count)"
    }
}

struct StackCard: View {
    let document: Document

    var body: some View {
        let group = document.group
        VStack(alignment: .leading) {
            HStack(spacing: 6) {
                Text(document.displayTitle)
                    .font(.system(size: 14, weight: .heavy))
                    .lineLimit(1)
                Spacer(minLength: 2)
                DaysChip(days: document.daysLeft(), onCardInk: group.ink)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: document.category.symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(document.cardSubtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .opacity(0.78)
        }
        .foregroundStyle(group.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(group.color, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: 0x0A0C14).opacity(0.12), radius: 8, y: -4)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Pusty pulpit

private struct EmptyHome: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dodaj pierwszy dokument")
                .font(.system(size: 22, weight: .heavy)).tracking(-0.5)
            Text("Przypomnimy 30 i 7 dni przed terminem oraz w dniu terminu.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.muted)
            Button { router.add(scan: true) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Palette.accentInk)
                        .frame(width: 46, height: 46)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Zeskanuj aparatem").font(.system(size: 16, weight: .heavy))
                        Text("Data ważności odczyta się sama").font(.system(size: 12, weight: .semibold)).opacity(0.7)
                    }
                    Spacer()
                }
                .foregroundStyle(Palette.bg)
                .padding(16)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(PressScaleStyle())

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach([DocumentCategory.carInsurance, .carInspection, .idCard, .subscription]) { cat in
                    Button { router.add(cat) } label: {
                        Label(cat.title, systemImage: cat.symbol)
                            .font(.system(size: 14, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(cat.group.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(cat.group.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
        }
        .padding(16)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}
