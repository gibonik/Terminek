import SwiftUI
import SwiftData

enum DocumentsFilter: Hashable {
    case all, expired, soon, group(CategoryGroup)

    func includes(_ doc: Document) -> Bool {
        switch self {
        case .all: true
        case .expired: doc.daysLeft() < 0
        case .soon: (0...30).contains(doc.daysLeft())
        case .group(let g): doc.group == g
        }
    }
}

/// Wszystkie dokumenty: wyszukiwarka, filtry i dwa widoki (lista albo karty).
struct DocumentsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Document.expiryDate) private var documents: [Document]

    @State private var filter: DocumentsFilter = .all
    @State private var search = ""
    @State private var showCards = false
    @FocusState private var searchFocused: Bool
    @Namespace private var modePill

    private var filtered: [Document] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return documents.filter { doc in
            guard filter.includes(doc) else { return false }
            guard !query.isEmpty else { return true }
            return [doc.displayTitle, doc.owner, doc.number, doc.category.title]
                .contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.lg) {
                header.riseIn(0)
                searchField.riseIn(1)
                filters.riseIn(2)

                if filtered.isEmpty {
                    emptyState
                } else if showCards {
                    cards
                } else {
                    list
                }
            }
            .padding(.top, DT.Space.xs)
            .padding(.bottom, DT.Space.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .onAppear {
            if let group = router.documentsGroup {
                filter = .group(group)
                router.documentsGroup = nil
            }
            if router.documentsSearch {
                router.documentsSearch = false
                searchFocused = true
            }
            Tilt.shared.start()
        }
        .onDisappear { Tilt.shared.stop() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DT.Space.xxs) {
                Text(documents.count == 1 ? "1 dokument" : "\(documents.count) dokumentów")
                    .font(DT.Typography.footnote)
                    .foregroundStyle(DT.Palette.textSecondary)
                    .contentTransition(.numericText())
                Text("Dokumenty").font(DT.Typography.largeTitle)
            }
            Spacer()
            HStack(spacing: 0) {
                modeButton("list.bullet", "Lista", isOn: !showCards) { showCards = false }
                modeButton("rectangle.portrait.on.rectangle.portrait", "Karty", isOn: showCards) { showCards = true }
            }
            .padding(DT.Space.xxs)
            .panelCapsule()
        }
        .padding(.horizontal, DT.Space.gutter)
    }

    private func modeButton(_ symbol: String, _ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(DT.Motion.bouncy) { action() } } label: {
            Image(systemName: symbol)
                .font(DT.Typography.subheadlineEmphasized)
                .foregroundStyle(isOn ? DT.Palette.onAccent : DT.Palette.textSecondary)
                .frame(width: DT.Size.touch, height: DT.Size.pill)
                .background {
                    if isOn {
                        Capsule().fill(DT.Palette.accent).matchedGeometryEffect(id: "mode", in: modePill)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var searchField: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(DT.Palette.textSecondary)
            TextField("", text: $search, prompt: Text("Szukaj: nazwa, osoba, numer").foregroundStyle(DT.Palette.textTertiary))
                .font(DT.Typography.body)
                .focused($searchFocused)
                .submitLabel(.search)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DT.Palette.textTertiary)
                }
                .frame(width: DT.Size.touch, height: DT.Size.touch)
                .accessibilityLabel("Wyczyść")
            }
        }
        .padding(.leading, DT.Space.md)
        .padding(.trailing, search.isEmpty ? DT.Space.md : 0)
        .frame(height: DT.Size.field)
        .panelCapsule()
        .padding(.horizontal, DT.Space.gutter)
    }

    private var filters: some View {
        let expired = documents.filter { $0.daysLeft() < 0 }.count
        let soon = documents.filter { (0...30).contains($0.daysLeft()) }.count
        return ScrollView(.horizontal) {
            HStack(spacing: DT.Space.xs) {
                Pill(title: "Wszystkie", isOn: filter == .all) { set(.all) }
                if expired > 0 {
                    Pill(title: "Po terminie · \(expired)", dot: DT.Palette.danger, isOn: filter == .expired) { set(.expired) }
                }
                if soon > 0 {
                    Pill(title: "30 dni · \(soon)", dot: DT.Palette.warning, isOn: filter == .soon) { set(.soon) }
                }
                ForEach(CategoryGroup.allCases) { group in
                    if documents.contains(where: { $0.group == group }) {
                        Pill(title: group.title, dot: group.color, isOn: filter == .group(group)) { set(.group(group)) }
                    }
                }
            }
        }
        .contentMargins(.horizontal, DT.Space.gutter, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    private func set(_ new: DocumentsFilter) {
        withAnimation(DT.Motion.standard) { filter = filter == new ? .all : new }
    }

    // MARK: Lista w sekcjach

    private var list: some View {
        let sections: [(ExpiryStatus, [Document])] = [ExpiryStatus.expired, .soon, .ok].compactMap { status -> (ExpiryStatus, [Document])? in
            let docs = filtered.filter { $0.status() == status }
            return docs.isEmpty ? nil : (status, docs)
        }
        return VStack(alignment: .leading, spacing: DT.Space.lg) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                VStack(alignment: .leading, spacing: DT.Space.sm) {
                    Text(section.0.sectionTitle.uppercased())
                        .font(DT.Typography.overline)
                        .kerning(DT.Size.hairline)
                        .foregroundStyle(section.0 == .expired ? DT.Palette.danger : DT.Palette.textSecondary)
                    VStack(spacing: 0) {
                        ForEach(Array(section.1.enumerated()), id: \.element.id) { i, doc in
                            if i > 0 {
                                Rectangle().fill(DT.Palette.separator).frame(height: DT.Size.hairline)
                                    .padding(.leading, DT.Space.md * 2 + DT.Size.miniCard.width)
                            }
                            Button { router.open(doc, from: "list-\(doc.id)") } label: { DocRow(document: doc) }
                                .buttonStyle(CardPressStyle())
                                .zoomSource("list-\(doc.id)")
                                .contextMenu { menu(doc) }
                        }
                    }
                    .panel()
                }
                .riseIn(3 + index)
            }
        }
        .padding(.horizontal, DT.Space.gutter)
        .animation(DT.Motion.standard, value: filtered.map(\.id))
    }

    // MARK: Karty jedna pod drugą

    private var cards: some View {
        LazyVStack(spacing: DT.Space.md) {
            ForEach(filtered) { doc in
                Button { router.open(doc, from: "card-\(doc.id)") } label: {
                    DocCard(data: CardData(doc))
                }
                .buttonStyle(CardPressStyle())
                .zoomSource("card-\(doc.id)")
                .contextMenu { menu(doc) }
                .scrollTransition(.interactive, axis: .vertical) { content, phase in
                    content
                        .scaleEffect(phase.isIdentity ? 1 : 0.88)
                        .opacity(phase.isIdentity ? 1 : 0.4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DT.Space.xs)
        .transition(.opacity)
    }

    private var emptyState: some View {
        VStack(spacing: DT.Space.sm) {
            Image(systemName: documents.isEmpty ? "rectangle.stack.badge.plus" : "magnifyingglass")
                .font(DT.Typography.largeTitle)
                .foregroundStyle(DT.Palette.textTertiary)
            Text(documents.isEmpty ? "Nie masz jeszcze dokumentów" : "Nic nie pasuje")
                .font(DT.Typography.title3)
            Text(documents.isEmpty ? "Dodaj pierwszy plusem na dole." : "Zmień filtr albo wyszukiwane słowo.")
                .font(DT.Typography.subheadline)
                .foregroundStyle(DT.Palette.textSecondary)
            if documents.isEmpty {
                PrimaryButton(title: "Dodaj dokument", symbol: "plus") { router.add() }
                    .padding(.top, DT.Space.sm)
                    .padding(.horizontal, DT.Space.xxl)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DT.Space.xxl)
    }

    @ViewBuilder
    private func menu(_ doc: Document) -> some View {
        Button { router.renew(doc) } label: {
            Label("Odnów do \(PL.date(doc.renewedExpiryDate()))", systemImage: "arrow.clockwise")
        }
        Button { router.edit(doc) } label: { Label("Edytuj", systemImage: "pencil") }
        Button(role: .destructive) { delete(doc) } label: { Label("Usuń", systemImage: "trash") }
    }

    private func delete(_ doc: Document) {
        let title = doc.displayTitle
        Haptics.shared.fire(.remove)
        withAnimation(.snappy) { context.delete(doc) }
        router.show("Usunięto „\(title)”", symbol: "trash.circle.fill")
    }
}
