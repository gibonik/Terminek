import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable, Identifiable {
    case home, wallet, calendar, account
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Start"
        case .wallet: "Dokumenty"
        case .calendar: "Kalendarz"
        case .account: "Konto"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .wallet: "rectangle.stack"
        case .calendar: "calendar"
        case .account: "person.crop.circle"
        }
    }
}

/// Otwarcie edytora: nowy dokument (z rodzajem albo od razu ze skanerem) lub edycja.
struct EditorRequest: Identifiable {
    let id = UUID()
    var document: Document?
    /// `nil` = najpierw pytamy o rodzaj.
    var category: DocumentCategory?
    var startScanning = false
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
    var undo: (() -> Void)?
    /// Napis na przycisku (domyślnie „Cofnij”).
    var actionTitle = "Cofnij"

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Wspólny stan: zakładka, otwarty dokument, edytor i komunikaty.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
    /// Dokument otwarty na pełnym ekranie.
    var opened: Document?
    /// Skąd go otwarto (karta w karuzeli, wiersz listy…), żeby przejście „zoom” wyszło z tego miejsca.
    var openedSource = ""
    var editor: EditorRequest?
    var toast: Toast?
    /// Grupa do pokazania po przejściu do zakładki Dokumenty (z rzędu na starcie).
    var documentsGroup: CategoryGroup?
    /// Po przejściu do Dokumentów od razu otwórz wyszukiwanie.
    var documentsSearch = false
    /// Czat z asystentem.
    var assistantOpen = false
    /// Ekran Terminek Plus.
    var paywall: PaywallReason?

    /// Pomoc do skrótów Siri (z Konta).
    var showShortcutsHelp = false

    /// Do zrzutów ekranu w CI: `-startTab home|wallet|calendar|account|detail|add`.
    private var launchAction: String?

    init() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-startTab"), i + 1 < args.count else { return }
        let value = args[i + 1]
        if let tab = AppTab(rawValue: value) {
            self.tab = tab
        } else {
            launchAction = value
        }
    }

    func open(_ document: Document, from source: String) {
        Haptics.shared.fire(.pull)
        openedSource = source
        opened = document
    }

    func close() {
        guard opened != nil else { return }
        Haptics.shared.fire(.stow)
        opened = nil
    }

    func add(_ category: DocumentCategory? = nil, scan: Bool = false) {
        let count = (try? TerminyApp.sharedContainer?.mainContext.fetchCount(FetchDescriptor<Document>())) ?? 0
        guard Store.shared.canAddDocument(currentCount: count) else {
            Haptics.shared.fire(.pull)
            paywall = .documents
            return
        }
        editor = EditorRequest(document: nil, category: category, startScanning: scan)
    }

    func edit(_ document: Document) {
        editor = EditorRequest(document: document, category: document.category)
    }

    func show(_ text: String, symbol: String = "checkmark.circle.fill", actionTitle: String = "Cofnij",
              duration: Double? = nil, undo: (() -> Void)? = nil) {
        let toast = Toast(text: text, symbol: symbol, undo: undo, actionTitle: actionTitle)
        self.toast = toast
        UIAccessibility.post(notification: .announcement, argument: text)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration ?? (undo == nil ? 2.6 : 4)))
            if self?.toast?.id == toast.id { self?.toast = nil }
        }
    }

    /// Zgłoszenie po potrząśnięciu: ze zrzutem tego, co było na ekranie.
    func reportFromShake() {
        guard !BugReportPresenter.isShowing, UserDefaults.standard.object(forKey: Self.shakeKey) as? Bool ?? true else { return }
        Haptics.shared.fire(.pull)
        BugReportPresenter.present(BugReportRequest(kind: .bug, screenshot: ScreenCapture.current()))
    }

    static let shakeKey = "shakeToReport"
    private static let lastCrashKey = "lastSeenCrashReport"

    /// Jeśli od ostatniego razu przyszedł nowy raport awarii, proponujemy jego wysłanie.
    func offerCrashReport() {
        guard !TerminyApp.isDemo, let latest = Diagnostics.shared.reports.first else { return }
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.lastCrashKey) != latest.lastPathComponent else { return }
        defaults.set(latest.lastPathComponent, forKey: Self.lastCrashKey)
        show("Aplikacja ostatnio się zamknęła. Wyślesz raport?", symbol: "ladybug.fill", actionTitle: "Wyślij", duration: 8) {
            BugReportPresenter.present(BugReportRequest(kind: .bug, crashReport: latest))
        }
    }

    /// Odnawia dokument i pokazuje komunikat z możliwością cofnięcia.
    func renew(_ document: Document) {
        let previous = document.expiryDate
        Haptics.shared.fire(.renew)
        Breadcrumbs.add("Odnowiono (\(document.category.rawValue))")
        withAnimation(DT.Motion.bouncy) { document.renew() }
        show("Odnowiono do \(PL.date(document.expiryDate))", symbol: "arrow.clockwise.circle.fill") { [weak document] in
            withAnimation { document?.expiryDate = previous }
        }
    }

    func runLaunchAction(firstDocument: Document?) {
        guard let action = launchAction else { return }
        launchAction = nil
        switch action {
        case "detail":
            if let firstDocument { open(firstDocument, from: "launch") }
        case "add":
            add()
        case "reminders", "settings":
            tab = .account
        case "assistant":
            assistantOpen = true
        case "paywall":
            paywall = .manual
        case "report":
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                BugReportPresenter.present(BugReportRequest())
            }
        case "shortcuts":
            tab = .account
            showShortcutsHelp = true
        default:
            break
        }
    }
}

// MARK: - Przejście „zoom” z karty do szczegółów (iOS 18+)

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

private struct ZoomSource: ViewModifier {
    let key: String
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            if let namespace {
                content.matchedTransitionSource(id: key, in: namespace) { source in
                    source.clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
                }
            } else {
                content
            }
        } else {
            content
        }
    }
}

private struct ZoomDestination: ViewModifier {
    let key: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: key, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    /// Miejsce, z którego „wyrasta” ekran szczegółów.
    func zoomSource(_ key: String) -> some View { modifier(ZoomSource(key: key)) }
}

// MARK: - Główny ekran

struct MainTabView: View {
    @State private var router = AppRouter()
    @Environment(\.modelContext) private var context
    @Namespace private var zoom

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()

            Group {
                switch router.tab {
                case .home: HomeView()
                case .wallet: DocumentsView()
                case .calendar: CalendarScreen()
                case .account: AccountView()
                }
            }
            .id(router.tab)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: DT.Space.sm)),
                                    removal: .opacity))

            VStack(spacing: DT.Space.sm) {
                if let toast = router.toast {
                    ToastView(toast: toast) {
                        toast.undo?()
                        router.toast = nil
                    }
                    .padding(.horizontal, DT.Space.gutter)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                }
                TabBar(selection: $router.tab) { router.add() }
            }
            .padding(.bottom, DT.Space.xs)
        }
        .foregroundStyle(DT.Palette.textPrimary)
        .animation(DT.Motion.bouncy, value: router.toast)
        .animation(.snappy(duration: 0.25), value: router.tab)
        .environment(router)
        .environment(\.zoomNamespace, zoom)
        .sheet(item: Binding(get: { router.opened == nil ? router.editor : nil }, set: { router.editor = $0 })) { request in
            DocumentEditView(request: request)
                .environment(router)
        }
        .sheet(item: $router.paywall) { reason in
            PaywallView(reason: reason)
        }
        .fullScreenCover(item: $router.opened) { doc in
            CardDetailView(document: doc)
                .modifier(ZoomDestination(key: router.openedSource, namespace: zoom))
                .environment(router)
        }
        .sensoryFeedback(.selection, trigger: router.tab)
        .onChange(of: DeepLink.shared.documentID, initial: true) { _, id in
            guard let id else { return }
            DeepLink.shared.documentID = nil
            let target = id
            let descriptor = FetchDescriptor<Document>(predicate: #Predicate { $0.id == target })
            guard let doc = try? context.fetch(descriptor).first else { return }
            router.editor = nil
            router.open(doc, from: "notification")
        }
        .onChange(of: DeepLink.shared.action, initial: true) { _, action in
            guard let action else { return }
            DeepLink.shared.action = nil
            handle(action)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in router.reportFromShake() }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            router.offerCrashReport()
        }
    }
}

extension MainTabView {
    /// Akcje ze skrótów Siri: zamykamy to, co otwarte, i przechodzimy we właściwe miejsce.
    fileprivate func handle(_ action: DeepLink.Action) {
        router.close()
        router.editor = nil
        switch action {
        case .add:
            router.tab = .home
            router.add()
        case .scan:
            router.tab = .home
            router.add(scan: true)
        case .assistant:
            router.tab = .home
            router.assistantOpen = true
        case .report:
            BugReportPresenter.present(BugReportRequest())
        }
    }
}

// MARK: - Pasek zakładek

/// Pływający pasek ze szkła z czterema zakładkami i osobnym przyciskiem „dodaj”.
struct TabBar: View {
    @Binding var selection: AppTab
    var onAdd: () -> Void
    @Namespace private var pill

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in item(tab) }
            }
            .padding(DT.Space.xxs)
            .glassBar(in: Capsule())

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(DT.Typography.title3)
                    .foregroundStyle(DT.Palette.onAccent)
                    .frame(width: DT.Size.tabItem.height + DT.Space.xs, height: DT.Size.tabItem.height + DT.Space.xs)
                    .background(DT.Palette.accent, in: Circle())
                    .shadow(color: DT.Palette.accent.opacity(0.55), radius: DT.Space.md, y: DT.Space.xs)
            }
            .buttonStyle(CardPressStyle())
            .accessibilityLabel("Dodaj dokument")
        }
        .padding(.horizontal, DT.Space.gutter)
    }

    private func item(_ tab: AppTab) -> some View {
        let isOn = selection == tab
        return Button {
            withAnimation(DT.Motion.bouncy) { selection = tab }
        } label: {
            VStack(spacing: DT.Size.hairline * 2) {
                Image(systemName: tab.symbol)
                    .symbolVariant(isOn ? .fill : .none)
                    .font(DT.Typography.headline)
                    .symbolEffect(.bounce, value: isOn)
                Text(tab.title)
                    .font(DT.Typography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? DT.Palette.textPrimary : DT.Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: DT.Size.tabItem.height)
            .background {
                if isOn {
                    Capsule()
                        .fill(DT.Palette.surfaceRaised)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct GlassBar<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(DT.Palette.separator, lineWidth: DT.Size.hairline))
            .shadow(color: DT.Palette.shadow, radius: DT.Space.lg, y: DT.Space.sm)
    }
}

extension View {
    func glassBar<S: Shape>(in shape: S) -> some View { modifier(GlassBar(shape: shape)) }
}

/// Komunikat nad paskiem.
struct ToastView: View {
    let toast: Toast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: toast.symbol)
                .font(DT.Typography.title3)
                .foregroundStyle(DT.Palette.accentText)
                .symbolEffect(.bounce, value: toast.id)
            Text(toast.text)
                .font(DT.Typography.subheadline)
                .foregroundStyle(DT.Palette.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if toast.undo != nil {
                Button(toast.actionTitle, action: onUndo)
                    .font(DT.Typography.subheadlineEmphasized)
                    .foregroundStyle(DT.Palette.accentText)
                    .frame(minHeight: DT.Size.touch)
            }
        }
        .padding(.leading, DT.Space.md)
        .padding(.trailing, toast.undo == nil ? DT.Space.md : DT.Space.sm)
        .frame(minHeight: DT.Size.toggleRow)
        .glassBar(in: Capsule())
        .accessibilityElement(children: .contain)
    }
}
