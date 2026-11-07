import SwiftUI
import SwiftData
import UserNotifications

/// Pulpit: panel (najbliżej, stan, abonamenty), przypomnienie, oś czasu, talie kart, podpowiedzi.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Document.expiryDate) private var documents: [Document]
    @AppStorage(NotificationScheduler.reminderHourKey) private var reminderHour = 9

    @State private var filter: CategoryGroup?
    @State private var openStack: String?
    @State private var renewTick = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header.riseIn(0)

                if documents.isEmpty {
                    EmptyHome()
                } else {
                    if let expired = documents.first(where: { $0.daysLeft() < 0 }) {
                        ExpiredBanner(document: expired) { renew(expired) }
                            .riseIn(1)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    topPanel.riseIn(2)
                    if let next = nextReminder { NextReminderStrip(reminder: next).riseIn(3) }
                    TimelineStrip(documents: documents) { router.selected = $0 }.riseIn(4)
                    filterRow.riseIn(5)
                    stacks.riseIn(6)
                    SuggestionsPanel(documents: documents).riseIn(7)
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
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Palette.accentInk)
                    .frame(width: 38, height: 38)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Terminy")
                    .font(.system(size: 26, weight: .heavy)).tracking(-0.8)
                    .foregroundStyle(Palette.ink)
            }
            Spacer()
            HStack(spacing: 8) {
                CircleIconButton(symbol: "magnifyingglass", label: "Szukaj") {
                    router.openList(.all, search: true)
                }
                CircleIconButton(symbol: "bell.fill", label: "Pilne: \(urgentCount)", badge: urgentCount) {
                    router.openList(.urgent)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: Panel

    private var hero: Document? {
        documents.first(where: { $0.daysLeft() >= 0 }) ?? documents.first
    }

    private var topPanel: some View {
        HStack(spacing: 10) {
            if let hero {
                HeroTile(document: hero, onOpen: { router.selected = hero }, onRenew: { renew(hero) })
                    .layoutPriority(1)
            }
            VStack(spacing: 10) {
                StatusTile(documents: documents) { router.openList(.urgent) }
                SubscriptionsTile(documents: documents) { router.openList(.group(.subscriptions)) }
            }
        }
        .frame(height: 256)
        .padding(10)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Color(hex: 0x14161F).opacity(0.07), radius: 15, y: 10)
    }

    // MARK: Następne przypomnienie

    private var nextReminder: (date: Date, title: String, offset: Int)? {
        let plan = NotificationScheduler.plannedReminders(
            for: documents, hour: reminderHour, now: .now, offsets: NotificationScheduler.enabledOffsets())
        guard let first = plan.first else { return nil }
        let offset = Int(first.identifier.split(separator: "-").last ?? "") ?? 0
        return (first.fireDate, first.title, offset)
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
            Text(days > 30 ? DaysText.long(to: document.expiryDate) : document.cardSubtitle)
                .font(.system(size: 12, weight: .semibold)).opacity(0.75)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

// MARK: - Kafel „stan”

private struct StatusTile: View {
    let documents: [Document]
    let onTap: () -> Void

    var body: some View {
        let expired = documents.filter { $0.daysLeft() < 0 }.count
        let soon = documents.filter { (0...30).contains($0.daysLeft()) }.count
        let ok = documents.count - expired - soon
        let bars: [(String, Int, Color)] = [
            ("Po terminie", expired, Palette.alert),
            ("Do 30 dni", soon, CategoryGroup.auto.color),
            ("Ważne", ok, CategoryGroup.personal.color),
        ].filter { $0.1 > 0 }

        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                Text("STAN")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Palette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(soon + ok)")
                        .font(.system(size: 26, weight: .heavy).monospacedDigit()).tracking(-1)
                        .contentTransition(.numericText())
                    Text("/ \(documents.count) ważnych")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(Palette.ink)
                GeometryReader { geo in
                    let total = max(CGFloat(documents.count), 1)
                    let gaps = CGFloat(max(bars.count - 1, 0)) * 3
                    HStack(spacing: 3) {
                        ForEach(bars.indices, id: \.self) { i in
                            let bar = bars[i]
                            Capsule().fill(bar.2)
                                .frame(width: max((geo.size.width - gaps) * CGFloat(bar.1) / total, 6))
                        }
                    }
                }
                .frame(height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(bars.indices, id: \.self) { i in
                            let bar = bars[i]
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(bar.2).frame(width: 6, height: 6)
                            Text(bar.0).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted)
                            Spacer(minLength: 2)
                            Text("\(bar.1)").font(.system(size: 11, weight: .heavy)).foregroundStyle(Palette.ink)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
    }
}

// MARK: - Kafel „abonamenty”

private struct SubscriptionsTile: View {
    let documents: [Document]
    let onTap: () -> Void

    var body: some View {
        let subs = documents.filter { $0.category == .subscription }
        let monthly = subs.reduce(0.0) { $0 + $1.monthlyCost }

        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ABONAMENTY")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Palette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(monthly.rounded().formatted(.number.precision(.fractionLength(0)).locale(PL.locale)))
                        .font(.system(size: 22, weight: .heavy).monospacedDigit()).tracking(-0.6)
                        .contentTransition(.numericText())
                    Text("zł/mies.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.muted)
                }
                .foregroundStyle(Palette.ink)
                if subs.isEmpty {
                    Text("brak").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted)
                } else {
                    GeometryReader { geo in
                        let gaps = CGFloat(max(subs.count - 1, 0)) * 3
                        HStack(spacing: 3) {
                            ForEach(Array(subs.enumerated()), id: \.element.id) { index, doc in
                                Capsule()
                                    .fill(index % 2 == 0 ? Color(hex: 0xE0A100) : CategoryGroup.subscriptions.color)
                                    .frame(width: max((geo.size.width - gaps) * CGFloat(doc.monthlyCost / max(monthly, 1)), 6))
                            }
                        }
                    }
                    .frame(height: 6)
                    Text(PL.money((monthly * 12).rounded()) + " rocznie")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
    }
}

// MARK: - Pasek „następne przypomnienie”

private struct NextReminderStrip: View {
    let reminder: (date: Date, title: String, offset: Int)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(CategoryGroup.subscriptions.ink)
                .frame(width: 38, height: 38)
                .background(CategoryGroup.subscriptions.color, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("NASTĘPNE PRZYPOMNIENIE")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.5).opacity(0.6)
                Text(when + " · " + reminder.title)
                    .font(.system(size: 14, weight: .heavy))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(reminder.offset == 0 ? "w dniu" : "\(reminder.offset) dni przed")
                .font(.system(size: 12, weight: .heavy)).opacity(0.6)
        }
        .foregroundStyle(Palette.bg)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var when: String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: reminder.date)
        if cal.isDateInToday(reminder.date) { return "Dziś \(hour):00" }
        if cal.isDateInTomorrow(reminder.date) { return "Jutro \(hour):00" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: reminder.date)).day ?? 0
        return days <= 14 ? "Za \(days) dni" : reminder.date.formatted(.dateTime.day().month(.abbreviated).locale(PL.locale))
    }
}

// MARK: - Oś czasu 90 dni

private struct TimelineStrip: View {
    let documents: [Document]
    let onOpen: (Document) -> Void

    var body: some View {
        let items = documents.filter { (0...90).contains($0.daysLeft()) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Najbliższe 90 dni").font(.system(size: 16, weight: .heavy))
                Spacer()
                Text(items.isEmpty ? "spokój" : "\(items.count) \(items.count == 1 ? "termin" : "terminów")")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 6)

            if items.isEmpty {
                Text("Przez najbliższe 3 miesiące nic nie wygasa.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(items) { doc in
                            Button { onOpen(doc) } label: { TimelineCard(document: doc) }
                                .buttonStyle(PressScaleStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -16)
            }
        }
    }
}

private struct TimelineCard: View {
    let document: Document

    var body: some View {
        let comps = PL.calendar.dateComponents([.day, .month], from: document.expiryDate)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(comps.day ?? 1)").font(.system(size: 22, weight: .heavy)).tracking(-0.6)
                    Text(PL.monthsShort[(comps.month ?? 1) - 1])
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 2)
                RoundedRectangle(cornerRadius: 4).fill(document.group.color).frame(width: 10, height: 10)
            }
            Text(document.displayTitle)
                .font(.system(size: 12, weight: .heavy))
                .lineLimit(1)
            DaysChip(document: document, size: 10)
        }
        .foregroundStyle(Palette.ink)
        .padding(10)
        .frame(width: 108, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Podpowiedzi

private struct SuggestionsPanel: View {
    let documents: [Document]
    @Environment(AppRouter.self) private var router

    var body: some View {
        let have = Set(documents.map(\.category))
        let missing = Array([DocumentCategory.carInsurance, .carInspection, .idCard, .passport, .homeInsurance, .drivingLicense]
            .filter { !have.contains($0) }
            .prefix(3))
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Może jeszcze to?").font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.ink)
                    Text("Najczęściej dodawane, których nie masz")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { chips(missing) }
                    VStack(alignment: .leading, spacing: 8) { chips(missing) }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    @ViewBuilder
    private func chips(_ cats: [DocumentCategory]) -> some View {
        ForEach(cats) { cat in
            Button { router.add(cat) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(cat.group.ink)
                        .frame(width: 22, height: 22)
                        .background(cat.group.color, in: Circle())
                    Text(cat.title).font(.system(size: 13, weight: .heavy)).lineLimit(1)
                }
                .foregroundStyle(Palette.ink)
                .padding(.leading, 7)
                .padding(.trailing, 12)
                .frame(height: 36)
                .background(Palette.tile, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
        }
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
                DaysChip(document: document, onCardInk: group.ink)
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

/// Dla nowych użytkowników: duży kafel, pierwsze kroki, szybkie kafle, jak to działa.
private struct EmptyHome: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppLock.self) private var lock
    @State private var pulse = false
    @State private var notificationsOn = false

    var body: some View {
        VStack(spacing: 14) {
            startTile.riseIn(1)
            stepsPanel.riseIn(2)
            quickAdd.riseIn(3)
            howItWorks.riseIn(4)
            privacy.riseIn(5)
        }
        .task { await refreshNotifications() }
    }

    // Duży kafel

    private var startTile: some View {
        Button { router.add() } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("NA START")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6).opacity(0.7)
                    Spacer()
                    Text("zajmie 30 sekund")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.12), in: Capsule())
                }
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Palette.accentInk.opacity(0.25))
                            .scaleEffect(pulse ? 1.35 : 0.85)
                            .opacity(pulse ? 0 : 0.9)
                        Circle().fill(Palette.accentInk)
                        Image(systemName: "plus")
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundStyle(Palette.accent)
                    }
                    .frame(width: 76, height: 76)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dodaj pierwszy dokument")
                            .font(.system(size: 25, weight: .heavy)).tracking(-0.8)
                            .multilineTextAlignment(.leading)
                        Text("Zeskanuj albo wpisz ręcznie")
                            .font(.system(size: 13, weight: .semibold)).opacity(0.75)
                    }
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(Palette.accentInk)
            .padding(20)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Palette.accent.opacity(0.35), radius: 18, y: 12)
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityLabel("Dodaj pierwszy dokument")
    }

    // Pierwsze kroki

    private var stepsPanel: some View {
        let done = [false, notificationsOn, lock.isEnabled].filter { $0 }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pierwsze kroki").font(.system(size: 17, weight: .heavy))
                Spacer()
                Text("\(done) z 3").font(.system(size: 13, weight: .heavy)).foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.ink)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.tile)
                    Capsule().fill(Palette.switchOn)
                        .frame(width: max(geo.size.width * CGFloat(done) / 3, 8))
                }
            }
            .frame(height: 8)
            .animation(.spring(duration: 0.6, bounce: 0.3), value: done)

            stepRow(done: false, title: "Dodaj pierwszy dokument", caption: "OC, dowód, paszport, abonament",
                    action: "Dodaj") { router.add() }
            stepRow(done: notificationsOn, title: "Włącz przypomnienia", caption: "30 i 7 dni przed oraz w dniu terminu",
                    action: "Włącz") {
                Task {
                    await NotificationScheduler.shared.requestAuthorization()
                    await refreshNotifications()
                }
            }
            stepRow(done: lock.isEnabled, title: "Zabezpiecz \(lock.biometryName)", caption: "Nikt nie podejrzy Twoich dokumentów",
                    action: "Włącz") { lock.isEnabled = true }
        }
        .padding(16)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func stepRow(done: Bool, title: String, caption: String, action: String,
                         perform: @escaping () -> Void) -> some View {
        Button(action: done ? {} : perform) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(done ? Palette.switchOn : Palette.panel)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(CategoryGroup.personal.ink)
                    }
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .heavy))
                        .strikethrough(done)
                    Text(caption)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(done ? "gotowe" : action)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(done ? Palette.switchOn : Palette.accent)
            }
            .foregroundStyle(Palette.ink)
            .padding(10)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
    }

    private func refreshNotifications() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        withAnimation { notificationsOn = status == .authorized || status == .provisional }
    }

    // Szybkie kafle

    private var quickAdd: some View {
        let items: [(DocumentCategory, String, String)] = [
            (.carInsurance, "OC auta", "co rok"),
            (.idCard, "Dowód osobisty", "co 10 lat"),
            (.passport, "Paszport", "co 10 lat"),
            (.subscription, "Abonament", "co miesiąc"),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            label("Co możesz śledzić")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(items.indices, id: \.self) { i in
                    let item = items[i]
                    Button { router.add(item.0) } label: {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(item.1).font(.system(size: 15, weight: .heavy)).lineLimit(1)
                                Spacer(minLength: 2)
                                Image(systemName: item.0.symbol).font(.system(size: 14, weight: .bold)).opacity(0.7)
                            }
                            Spacer(minLength: 0)
                            Text(item.2).font(.system(size: 12, weight: .semibold)).opacity(0.75)
                        }
                        .foregroundStyle(item.0.group.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(height: 92)
                        .background(item.0.group.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
        }
    }

    // Jak to działa

    private var howItWorks: some View {
        let steps: [(String, String, String, CategoryGroup)] = [
            ("1", "Zeskanuj", "Aparat odczyta datę ważności z dokumentu.", .auto),
            ("2", "Zapomnij", "Przypomnimy 30 i 7 dni przed oraz w dniu terminu.", .home),
            ("3", "Odnów", "Jedno stuknięcie „Odnowione” przesuwa termin.", .personal),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            label("Jak to działa")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(steps.indices, id: \.self) { i in
                        let step = steps[i]
                        VStack(alignment: .leading, spacing: 10) {
                            Text(step.0)
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(step.3.ink)
                                .frame(width: 34, height: 34)
                                .background(step.3.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(step.1).font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.ink)
                            Text(step.2)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(width: 220, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
        }
    }

    private var privacy: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 17, weight: .bold))
                .frame(width: 40, height: 40)
                .background(Palette.bg.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Tylko dla Ciebie").font(.system(size: 14, weight: .heavy))
                Text("\(lock.biometryName) i Twój iCloud. Bez kont i reklam.")
                    .font(.system(size: 12, weight: .semibold)).opacity(0.7)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.bg)
        .padding(14)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy)).tracking(0.6)
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 6)
    }
}
