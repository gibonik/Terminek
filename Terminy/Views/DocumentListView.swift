import SwiftUI
import SwiftData

/// Zakładka „Dokumenty”: wyszukiwarka, filtry i wszystkie dokumenty pogrupowane wg pilności.
struct DocumentListView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Document.expiryDate) private var documents: [Document]

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var toDelete: Document?

    private var filter: ListFilter { router.listFilter }

    private func matches(_ doc: Document, _ filter: ListFilter) -> Bool {
        switch filter {
        case .all: true
        case .urgent: doc.daysLeft() <= 7
        case .group(let group): doc.group == group
        }
    }

    private var filtered: [Document] {
        documents.filter { doc in
            matches(doc, filter)
                && (searchText.isEmpty
                    || doc.displayTitle.localizedCaseInsensitiveContains(searchText)
                    || doc.owner.localizedCaseInsensitiveContains(searchText)
                    || doc.number.localizedCaseInsensitiveContains(searchText)
                    || doc.notes.localizedCaseInsensitiveContains(searchText)
                    || doc.category.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var sections: [(title: String, docs: [Document])] {
        let docs = filtered
        return [
            ("Po terminie", docs.filter { $0.daysLeft() < 0 }),
            ("Do 30 dni", docs.filter { (0...30).contains($0.daysLeft()) }),
            ("Później", docs.filter { $0.daysLeft() > 30 }),
        ].filter { !$0.docs.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Dokumenty", subtitle: "\(documents.count) w sumie").riseIn(0)
                searchField.riseIn(1)
                filterRow.riseIn(2)

                if filtered.isEmpty {
                    emptyState.riseIn(3)
                } else {
                    ForEach(Array(sections.enumerated()), id: \.element.title) { index, section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title.uppercased())
                                .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(section.title == "Po terminie" ? Palette.alert : Palette.muted)
                                .padding(.horizontal, 6)
                                .padding(.top, 4)
                            ForEach(section.docs) { doc in
                                DocumentRow(document: doc)
                                    .onTapGesture { router.selected = doc }
                                    .contextMenu {
                                        Button { withAnimation { doc.renew() } } label: {
                                            Label("Odnowione", systemImage: "checkmark")
                                        }
                                        Button { router.edit(doc) } label: { Label("Edytuj", systemImage: "pencil") }
                                        Button(role: .destructive) { toDelete = doc } label: {
                                            Label("Usuń", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .riseIn(3 + index)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .animation(.spring(duration: 0.45, bounce: 0.2), value: filtered.map(\.id))
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .tabBarClearance()
        .background(Palette.bg.ignoresSafeArea())
        .onAppear(perform: applyFocusRequest)
        .onChange(of: router.focusSearch) { applyFocusRequest() }
        .sheet(item: $toDelete) { doc in
            ConfirmDeleteSheet(document: doc)
        }
    }

    private func applyFocusRequest() {
        guard router.focusSearch else { return }
        router.focusSearch = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            searchFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.muted)
            TextField("Szukaj: nazwa, osoba, numer", text: $searchText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                }
                .accessibilityLabel("Wyczyść")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                pill("Wszystko", dot: filter == .all ? Palette.bg : Palette.ink, .all)
                pill("Pilne", dot: Palette.alert, .urgent)
                ForEach(CategoryGroup.allCases) { group in
                    pill(group.title, dot: group.color, .group(group))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func pill(_ title: String, dot: Color, _ value: ListFilter) -> some View {
        FilterPill(title: title, dot: dot,
                   count: documents.filter { matches($0, value) }.count,
                   isOn: filter == value) {
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { router.listFilter = value }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: documents.isEmpty ? "doc.badge.plus" : "magnifyingglass")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Palette.muted)
            Text(documents.isEmpty ? "Nie masz jeszcze dokumentów" : "Nic nie pasuje")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Palette.ink)
            if documents.isEmpty {
                Button { router.add() } label: {
                    Text("Dodaj dokument")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Palette.accentInk)
                        .padding(.horizontal, 20)
                        .frame(height: 46)
                        .background(Palette.accent, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Wiersz listy: kolorowy kwadrat z ikoną, nazwa, podpis i plakietka dni.
struct DocumentRow: View {
    let document: Document

    var body: some View {
        let group = document.group
        HStack(spacing: 12) {
            Image(systemName: document.category.symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(group.ink)
                .frame(width: 42, height: 42)
                .background(group.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(document.displayTitle)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(group.title + " · " + document.cardSubtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            DaysChip(document: document, size: 12)
        }
        .padding(12)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
