import SwiftUI
import SwiftData

struct DocumentListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Document.expiryDate) private var documents: [Document]

    @State private var categoryFilter: DocumentCategory?
    @State private var searchText = ""
    @State private var editorTemplate: DocumentCategory?
    @State private var showingNew = false
    @State private var showingSettings = false

    private var filtered: [Document] {
        documents.filter { doc in
            (categoryFilter == nil || doc.category == categoryFilter)
            && (searchText.isEmpty
                || doc.displayTitle.localizedCaseInsensitiveContains(searchText)
                || doc.owner.localizedCaseInsensitiveContains(searchText)
                || doc.number.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var grouped: [ExpiryStatus: [Document]] {
        Dictionary(grouping: filtered) { $0.status() }
    }

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Terminy")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Ustawienia")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(DocumentCategory.allCases) { category in
                            Button { newDocument(category) } label: {
                                Label(category.title, systemImage: category.symbol)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    } primaryAction: {
                        newDocument(.other)
                    }
                    .accessibilityLabel("Dodaj dokument")
                }
            }
            .sheet(isPresented: $showingNew) {
                DocumentEditView(document: nil, initialCategory: editorTemplate ?? .other)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        FilterChip(title: "Wszystkie", isOn: categoryFilter == nil) { categoryFilter = nil }
                        ForEach(DocumentCategory.allCases) { category in
                            FilterChip(title: category.title, isOn: categoryFilter == category) {
                                categoryFilter = categoryFilter == category ? nil : category
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            let byStatus = grouped
            ForEach([ExpiryStatus.expired, .soon, .ok], id: \.self) { status in
                if let docs = byStatus[status] {
                    Section(status.sectionTitle) {
                        ForEach(docs) { doc in
                            NavigationLink(value: doc) {
                                DocumentRow(document: doc)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    withAnimation { doc.renew() }
                                } label: {
                                    Label("Odnów", systemImage: "arrow.clockwise")
                                }
                                .tint(.green)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(docs[index]) }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Szukaj: nazwa, osoba, numer")
        .navigationDestination(for: Document.self) { DocumentDetailView(document: $0) }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Brak dokumentów", systemImage: "doc.badge.clock")
        } description: {
            Text("Dodaj OC, przegląd, paszport albo subskrypcję. Przypomnimy 30 i 7 dni przed terminem.")
        } actions: {
            Button("Dodaj ubezpieczenie OC") { newDocument(.carInsurance) }
                .buttonStyle(.borderedProminent)
            Button("Dodaj inny dokument") { newDocument(.other) }
        }
    }

    private func newDocument(_ category: DocumentCategory) {
        editorTemplate = category
        showingNew = true
    }
}

struct DocumentRow: View {
    let document: Document

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.category.symbol)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.displayTitle).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            DaysLeftBadge(daysLeft: document.daysLeft())
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !document.owner.isEmpty { parts.append(document.owner) }
        parts.append(document.expiryDate.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }
}

struct DaysLeftBadge: View {
    let daysLeft: Int

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch daysLeft {
        case ..<0: "\(-daysLeft) dni po"
        case 0: "dziś"
        case 1: "jutro"
        default: "\(daysLeft) dni"
        }
    }

    private var color: Color {
        switch ExpiryStatus(daysLeft: daysLeft) {
        case .expired: .red
        case .soon: daysLeft <= 7 ? .orange : .yellow
        case .ok: .green
        }
    }
}

struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
