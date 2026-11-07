import SwiftUI
import SwiftData

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
        case .settings: "slider.horizontal.3"
        }
    }
}

/// Filtr listy dokumentów (pulpit może przełączyć na listę z gotowym filtrem).
enum ListFilter: Hashable {
    case all, urgent, group(CategoryGroup)
}

/// Otwarcie edytora: nowy dokument (z kategorią albo od razu ze skanerem) lub edycja.
struct EditorRequest: Identifiable {
    let id = UUID()
    var document: Document?
    /// `nil` = najpierw pytamy „Co dodajesz?”.
    var category: DocumentCategory?
    var startScanning = false
}

/// Wspólny stan nawigacji i arkuszy dla wszystkich zakładek.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab
    var listFilter: ListFilter = .all
    var focusSearch = false

    var selected: Document?
    var showingAdd = false
    var editor: EditorRequest?
    /// Edytor czeka, aż zamknie się arkusz „Nowy dokument” (dwa arkusze naraz iOS nie pokaże).
    var pendingEditor: EditorRequest?

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count, let tab = AppTab(rawValue: args[i + 1]) {
            self.tab = tab
        } else {
            self.tab = .home
        }
    }

    func openList(_ filter: ListFilter, search: Bool = false) {
        listFilter = filter
        focusSearch = search
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { tab = .documents }
    }

    func add(_ category: DocumentCategory? = nil, scan: Bool = false) {
        present(EditorRequest(document: nil, category: category, startScanning: scan))
    }

    func edit(_ document: Document) {
        present(EditorRequest(document: document, category: document.category))
    }

    private func present(_ request: EditorRequest) {
        if showingAdd {
            pendingEditor = request
            showingAdd = false
        } else if selected != nil {
            pendingEditor = request
            selected = nil
        } else {
            editor = request
        }
    }

    func showPendingEditor() {
        guard let pending = pendingEditor else { return }
        pendingEditor = nil
        editor = pending
    }
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
                router.add()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 8)
        }
        .background(Palette.bg.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(router)
        .sheet(item: $router.selected, onDismiss: { router.showPendingEditor() }) { doc in
            DocumentSheet(document: doc)
                .environment(router)
        }
        .sheet(item: $router.editor) { request in
            DocumentEditView(document: request.document,
                             initialCategory: request.category,
                             startScanning: request.startScanning)
        }
        .sensoryFeedback(.selection, trigger: router.tab)
    }
}

/// Pływający ciemny pasek: 4 zakładki + pomarańczowy plus pośrodku.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    var onAdd: () -> Void
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            item(.home)
            Spacer(minLength: 0)
            item(.documents)
            Spacer(minLength: 0)
            addButton
            Spacer(minLength: 0)
            item(.calendar)
            Spacer(minLength: 0)
            item(.settings)
        }
        .padding(.horizontal, 8)
        .frame(height: 64)
        .background(Palette.nav, in: Capsule())
        .shadow(color: Color(hex: 0x0A0C14).opacity(0.28), radius: 16, y: 8)
    }

    private func item(_ tab: AppTab) -> some View {
        let isOn = selection == tab
        return Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { selection = tab }
        } label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 19, weight: .bold))
                .symbolEffect(.bounce, value: isOn)
                .foregroundStyle(isOn ? Palette.navOn : Palette.navOff)
                .frame(width: 54, height: 48)
                .background {
                    if isOn {
                        Capsule()
                            .fill(Palette.navOnBg)
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Palette.accentInk)
                .frame(width: 54, height: 54)
                .background(Palette.accent, in: Circle())
                .shadow(color: Palette.accent.opacity(0.45), radius: 8, y: 6)
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .accessibilityLabel("Dodaj dokument")
    }
}
