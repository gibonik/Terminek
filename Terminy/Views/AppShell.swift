import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable, Identifiable {
    case home, calendar, settings
    var id: String { rawValue }
}

/// Otwarcie edytora: nowy dokument (z rodzajem albo od razu ze skanerem) lub edycja.
struct EditorRequest: Identifiable {
    let id = UUID()
    var document: Document?
    /// `nil` = najpierw pytamy „Co dodajesz?”.
    var category: DocumentCategory?
    var startScanning = false
}

/// Wspólny stan nawigacji: zakładka, ścieżki stosów i arkusz edytora.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var homePath: [Document] = []
    var calendarPath: [Document] = []
    var editor: EditorRequest?

    /// Do zrzutów ekranu w CI: `-startTab home|calendar|settings|detail|add`.
    private var launchAction: String?

    init() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-startTab"), i + 1 < args.count else { return }
        let value = args[i + 1]
        switch value {
        case "calendar": tab = .calendar
        case "settings": tab = .settings
        case "detail", "add": launchAction = value
        default: tab = .home
        }
    }

    func add(_ category: DocumentCategory? = nil, scan: Bool = false) {
        editor = EditorRequest(document: nil, category: category, startScanning: scan)
    }

    func edit(_ document: Document) {
        editor = EditorRequest(document: document, category: document.category)
    }

    /// Wykonuje akcję startową raz, gdy dane są już wczytane.
    func runLaunchAction(firstDocument: Document?) {
        guard let action = launchAction else { return }
        launchAction = nil
        switch action {
        case "detail":
            if let firstDocument { homePath = [firstDocument] }
        case "add":
            add()
        default:
            break
        }
    }
}

struct MainTabView: View {
    @State private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.tab) {
            DeadlinesView()
                .tabItem { Label("Terminy", systemImage: "doc.text") }
                .tag(AppTab.home)

            CalendarScreen()
                .tabItem { Label("Kalendarz", systemImage: "calendar") }
                .tag(AppTab.calendar)

            SettingsView()
                .tabItem { Label("Ustawienia", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .environment(router)
        .sheet(item: $router.editor) { request in
            DocumentEditView(request: request)
        }
        .sensoryFeedback(.selection, trigger: router.tab)
    }
}
