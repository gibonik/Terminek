import SwiftUI
import SwiftData

/// Grupa wierszy na liście terminów: „Po terminie”, miesiąc albo rok.
struct DeadlineSection: Identifiable {
    enum Kind { case expired, month, year }

    let id: String
    let title: String
    let kind: Kind
    var documents: [Document]

    /// Dokumenty posortowane po dacie: najpierw po terminie, potem kolejne miesiące
    /// (przez najbliższy rok), a dalsze terminy zbiorczo po latach.
    static func build(from documents: [Document], now: Date = .now) -> [DeadlineSection] {
        let cal = PL.calendar
        let today = cal.startOfDay(for: now)
        let yearAhead = cal.date(byAdding: .month, value: 12, to: today) ?? today
        let currentYear = cal.component(.year, from: today)

        var result: [DeadlineSection] = []
        for doc in documents.sorted(by: { $0.expiryDate < $1.expiryDate }) {
            let date = cal.startOfDay(for: doc.expiryDate)
            let year = cal.component(.year, from: date)
            let key: String
            let title: String
            let kind: Kind
            if date < today {
                key = "expired"; title = "Po terminie"; kind = .expired
            } else if date < yearAhead {
                let month = cal.component(.month, from: date)
                key = "m\(year)-\(month)"
                title = year == currentYear ? PL.months[month - 1] : "\(PL.months[month - 1]) \(year)"
                kind = .month
            } else {
                key = "y\(year)"; title = "\(year)"; kind = .year
            }
            if result.last?.id == key {
                result[result.count - 1].documents.append(doc)
            } else {
                result.append(DeadlineSection(id: key, title: title, kind: kind, documents: [doc]))
            }
        }
        return result
    }
}

/// Główna zakładka: najbliższy termin u góry, pod nim wszystko po kolei jak w terminarzu.
struct DeadlinesView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Document.expiryDate) private var documents: [Document]
    @State private var search = ""
    @State private var filter: CategoryGroup?
    @State private var renewTick = 0

    private var visible: [Document] {
        documents.filter { doc in
            (filter == nil || doc.group == filter) &&
            (search.isEmpty
             || doc.displayTitle.localizedStandardContains(search)
             || doc.owner.localizedStandardContains(search)
             || doc.number.localizedStandardContains(search))
        }
    }

    private var nextUp: Document? {
        visible.first { $0.daysLeft() >= 0 }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.homePath) {
            Group {
                if documents.isEmpty {
                    EmptyStartView()
                } else {
                    list
                }
            }
            .navigationTitle(filter?.title ?? "Terminy")
            .toolbar { toolbar }
            .navigationDestination(for: Document.self) { DocumentDetailView(document: $0) }
        }
        .sensoryFeedback(.success, trigger: renewTick)
        .onAppear {
            router.runLaunchAction(firstDocument: documents.first { $0.daysLeft() >= 0 } ?? documents.first)
        }
    }

    private var list: some View {
        let sections = DeadlineSection.build(from: visible)
        return List {
            if search.isEmpty, let nextUp {
                Section {
                    Button { router.homePath.append(nextUp) } label: {
                        NextUpView(document: nextUp)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
                }
            }

            ForEach(sections) { section in
                Section {
                    ForEach(section.documents) { doc in
                        NavigationLink(value: doc) {
                            DocumentRow(document: doc, caption: section.kind == .year ? .month : .weekday)
                        }
                        .swipeActions(edge: .leading) {
                            Button { renew(doc) } label: { Label("Odnów", systemImage: "arrow.clockwise") }
                                .tint(Palette.tint)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { context.delete(doc) } label: {
                                Label("Usuń", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button { renew(doc) } label: {
                                Label("Odnów do \(PL.date(doc.renewedExpiryDate()))", systemImage: "arrow.clockwise")
                            }
                            Button { router.edit(doc) } label: { Label("Edytuj", systemImage: "pencil") }
                            Button(role: .destructive) { context.delete(doc) } label: {
                                Label("Usuń", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(section.title)
                        .foregroundStyle(section.kind == .expired ? Palette.expired : Color.primary)
                }
                .headerProminence(.increased)
            }

            if search.isEmpty, filter == nil || filter == .subscriptions, let summary = subscriptionsSummary {
                Section { EmptyView() } footer: { Text(summary) }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .searchable(text: $search, prompt: "Szukaj po nazwie, osobie lub numerze")
        .overlay {
            if visible.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("Brak dokumentów w grupie \(filter?.title ?? "")",
                                           systemImage: filter?.symbol ?? "doc.text",
                                           description: Text("Zmień filtr albo dodaj dokument."))
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        .animation(.default, value: filter)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !documents.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Pokaż", selection: $filter) {
                        Text("Wszystkie").tag(CategoryGroup?.none)
                        ForEach(CategoryGroup.allCases) { group in
                            Label(group.title, systemImage: group.symbol).tag(CategoryGroup?.some(group))
                        }
                    }
                } label: {
                    Label("Filtr", systemImage: filter == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { router.add() } label: { Label("Dodaj dokument", systemImage: "plus") }
        }
    }

    private var subscriptionsSummary: String? {
        let subs = documents.filter { $0.category == .subscription }
        guard !subs.isEmpty else { return nil }
        let total = subs.reduce(0.0) { $0 + $1.monthlyCost }
        let n = subs.count
        let few = (2...4).contains(n % 10) && !(12...14).contains(n % 100)
        let noun = n == 1 ? "abonament" : (few ? "abonamenty" : "abonamentów")
        let verb = few ? "kosztują" : "kosztuje"
        guard total > 0 else { return "\(n) \(noun)." }
        return "\(n) \(noun) \(verb) razem \(PL.money(total)) miesięcznie."
    }

    private func renew(_ doc: Document) {
        withAnimation { doc.renew() }
        renewTick += 1
    }
}

// MARK: - Najbliższy termin

/// Jedyny duży element pulpitu: ile zostało do najbliższego terminu.
struct NextUpView: View {
    let document: Document

    var body: some View {
        let days = document.daysLeft()
        VStack(alignment: .leading, spacing: 2) {
            Text("Najbliższy termin")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(bigText(days))
                .font(.system(size: 60, weight: .bold))
                .tracking(-1.5)
                .monospacedDigit()
                .foregroundStyle(days <= 7 ? Urgency(days: days).color : Color.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(document.displayTitle)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Pokazuje szczegóły dokumentu")
    }

    private func bigText(_ days: Int) -> String {
        switch days {
        case 0: return "Dziś"
        case 1: return "Jutro"
        default: return DaysText.headline(to: document.expiryDate).big
        }
    }

    private var detail: String {
        let when = PL.dayMonth(document.expiryDate)
        let what = document.category == .subscription ? "płatność \(when)" : "ważne do \(when)"
        return document.owner.isEmpty ? String(what.prefix(1)).uppercased() + String(what.dropFirst()) : "\(document.owner), \(what)"
    }
}

// MARK: - Wiersz

/// Wiersz jak w terminarzu: dzień miesiąca po lewej, nazwa, a po prawej ile zostało.
struct DocumentRow: View {
    enum Caption { case weekday, month }

    let document: Document
    var caption: Caption = .weekday
    @ScaledMetric(relativeTo: .title2) private var dateWidth: CGFloat = 38

    private static let monthsShort = ["sty", "lut", "mar", "kwi", "maj", "cze", "lip", "sie", "wrz", "paź", "lis", "gru"]

    var body: some View {
        let days = document.daysLeft()
        let urgency = Urgency(days: days)
        HStack(spacing: 14) {
            VStack(spacing: -1) {
                Text(PL.calendar.component(.day, from: document.expiryDate).formatted())
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(captionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: dateWidth)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle()
                        .fill(document.group.color)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(document.detailLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(DaysText.compact(to: document.expiryDate))
                .font(.subheadline.weight(urgency == .later ? .regular : .semibold))
                .monospacedDigit()
                .foregroundStyle(urgency.color)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(days < 0 ? "po terminie" : DaysText.sentence(days))
    }

    private var captionText: String {
        switch caption {
        case .weekday:
            return PL.weekday(document.expiryDate)
        case .month:
            return Self.monthsShort[PL.calendar.component(.month, from: document.expiryDate) - 1]
        }
    }
}

// MARK: - Pusty start

/// Pierwsze uruchomienie: zamiast pustego ekranu najczęstsze dokumenty do dodania jednym stuknięciem.
struct EmptyStartView: View {
    @Environment(AppRouter.self) private var router

    private let common: [DocumentCategory] = [.carInsurance, .carInspection, .idCard, .drivingLicense, .passport, .subscription]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dodaj pierwszy dokument")
                        .font(.title2.weight(.bold))
                    Text("Terminy przypomną Ci o końcu ważności miesiąc wcześniej, tydzień wcześniej i w dniu terminu.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
            }

            if DocumentScanner.isSupported {
                Section {
                    Button { router.add(scan: true) } label: {
                        Label("Zeskanuj dokument", systemImage: "doc.viewfinder")
                    }
                } footer: {
                    Text("Aparat odczyta datę ważności. Zdjęcie zostaje na telefonie.")
                }
            }

            Section("Najczęściej dodawane") {
                ForEach(common) { category in
                    Button { router.add(category) } label: {
                        Label {
                            Text(category.title).foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: category.symbol).foregroundStyle(category.group.color)
                        }
                    }
                }
                Button { router.add() } label: {
                    Label("Coś innego", systemImage: "ellipsis.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
