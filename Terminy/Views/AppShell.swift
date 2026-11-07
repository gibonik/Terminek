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
    var toast: Toast?

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

    /// Krótki komunikat na dole ekranu, opcjonalnie z „Cofnij”.
    func show(_ text: String, symbol: String = "checkmark.circle.fill", undo: (() -> Void)? = nil) {
        let toast = Toast(text: text, symbol: symbol, undo: undo)
        self.toast = toast
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(undo == nil ? 2.6 : 4))
            if self?.toast?.id == toast.id { self?.toast = nil }
        }
    }

    /// Odnawia dokument i pokazuje komunikat z możliwością cofnięcia.
    func renew(_ document: Document) {
        let previous = document.expiryDate
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { document.renew() }
        show("Odnowiono do \(PL.date(document.expiryDate))", symbol: "arrow.clockwise.circle.fill") { [weak document] in
            withAnimation { document?.expiryDate = previous }
        }
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

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
    var undo: (() -> Void)?

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

struct MainTabView: View {
    @State private var router = AppRouter()
    @Environment(\.modelContext) private var context

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
        .overlay(alignment: .bottom) {
            if let toast = router.toast {
                ToastView(toast: toast) {
                    toast.undo?()
                    router.toast = nil
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 92)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: router.toast)
        .environment(router)
        .sheet(item: $router.editor) { request in
            DocumentEditView(request: request)
                .environment(router)
        }
        .sensoryFeedback(.selection, trigger: router.tab)
        .sensoryFeedback(.success, trigger: router.toast?.id) { _, new in new != nil }
        .onChange(of: DeepLink.shared.documentID, initial: true) { _, id in
            guard let id else { return }
            DeepLink.shared.documentID = nil
            let target = id
            let descriptor = FetchDescriptor<Document>(predicate: #Predicate { $0.id == target })
            guard let doc = try? context.fetch(descriptor).first else { return }
            router.editor = nil
            router.tab = .home
            router.homePath = [doc]
        }
    }
}

/// Komunikat w szkle nad paskiem kart.
struct ToastView: View {
    let toast: Toast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(.title3)
                .foregroundStyle(Palette.tint)
                .symbolEffect(.bounce, value: toast.id)
            Text(toast.text)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if toast.undo != nil {
                Button("Cofnij", action: onUndo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.tint)
                    .frame(minHeight: 44)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, toast.undo == nil ? 16 : 12)
        .frame(minHeight: 52)
        .glassCapsule()
        .accessibilityElement(children: .contain)
    }
}
