import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, documents, calendar, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Pulpit"
        case .documents: "Dokumenty"
        case .calendar: "Kalendarz"
        case .settings: "Ustawienia"
        }
    }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .documents: "doc.text.fill"
        case .calendar: "calendar"
        case .settings: "gearshape.fill"
        }
    }
}

/// Wspólny stan nawigacji: pulpit może przełączyć na listę z gotowym filtrem.
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var listFilter: ListFilter = .all
    var newDocumentCategory: DocumentCategory?

    func open(_ filter: ListFilter) {
        listFilter = filter
        tab = .documents
    }
}

enum ListFilter: Hashable {
    case all, attention, category(DocumentCategory)
}

struct MainTabView: View {
    @State private var router = AppRouter()

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $router.tab) {
                HomeView().tag(AppTab.home).toolbar(.hidden, for: .tabBar)
                DocumentListView().tag(AppTab.documents).toolbar(.hidden, for: .tabBar)
                CalendarView().tag(AppTab.calendar).toolbar(.hidden, for: .tabBar)
                SettingsView().tag(AppTab.settings).toolbar(.hidden, for: .tabBar)
            }

            FloatingTabBar(selection: $router.tab) {
                router.newDocumentCategory = .other
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .environment(router)
        .sheet(item: $router.newDocumentCategory) { category in
            DocumentEditView(document: nil, initialCategory: category)
        }
        .sensoryFeedback(.selection, trigger: router.tab)
    }
}

/// Pływający pasek na dole: 4 zakładki + duży przycisk dodawania pośrodku.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    var onAdd: () -> Void
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            item(.home)
            item(.documents)
            addButton
            item(.calendar)
            item(.settings)
        }
        .padding(6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
                .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        }
    }

    private func item(_ tab: AppTab) -> some View {
        let isOn = selection == tab
        return Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolEffect(.bounce, value: isOn)
                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isOn {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.14))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.accentColor.gradient))
                .shadow(color: Color.accentColor.opacity(0.45), radius: 10, y: 4)
        }
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, 4)
        .accessibilityLabel("Dodaj dokument")
    }
}

/// Lekkie „wciśnięcie” przycisków.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

extension View {
    /// Miejsce na pływający pasek, żeby nie zasłaniał ostatnich wierszy.
    func tabBarClearance() -> some View {
        contentMargins(.bottom, 96, for: .scrollContent)
    }
}
