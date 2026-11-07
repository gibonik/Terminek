import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable, Identifiable {
    case home, calendar, reminders, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Portfel"
        case .calendar: "Kalendarz"
        case .reminders: "Przypomnienia"
        case .settings: "Ustawienia"
        }
    }

    var symbol: String {
        switch self {
        case .home: "wallet.pass"
        case .calendar: "calendar"
        case .reminders: "bell"
        case .settings: "gearshape"
        }
    }
}

/// Otwarcie edytora: nowy dokument (z rodzajem albo od razu ze skanerem) lub edycja.
struct EditorRequest: Identifiable {
    let id = UUID()
    var document: Document?
    /// `nil` = najpierw pytamy „Co wkładasz do portfela?”.
    var category: DocumentCategory?
    var startScanning = false
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
    var undo: (() -> Void)?

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Wspólny stan: zakładka, otwarta karta, edytor i komunikaty.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
    /// Karta wyciągnięta z portfela (szczegóły).
    var opened: Document?
    var editor: EditorRequest?
    var toast: Toast?

    /// Do zrzutów ekranu w CI: `-startTab home|calendar|reminders|settings|detail|add`.
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

    func open(_ document: Document) {
        Haptics.shared.fire(.pull)
        withAnimation(DT.Motion.open) { opened = document }
    }

    func close() {
        guard opened != nil else { return }
        Haptics.shared.fire(.stow)
        withAnimation(DT.Motion.close) { opened = nil }
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
        Haptics.shared.fire(.renew)
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
            if let firstDocument { opened = firstDocument }
        case "add":
            add()
        default:
            break
        }
    }
}

struct MainTabView: View {
    @State private var router = AppRouter()
    @Environment(\.modelContext) private var context
    @Namespace private var cards

    var body: some View {
        ZStack(alignment: .bottom) {
            WalletBackground()

            Group {
                switch router.tab {
                case .home: WalletView(cards: cards)
                case .calendar: CalendarScreen()
                case .reminders: RemindersView()
                case .settings: SettingsView()
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .id(router.tab)

            Dock(selection: $router.tab) { router.add() }
                .padding(.bottom, DT.Space.xs)
                .opacity(router.opened == nil ? 1 : 0)
                .offset(y: router.opened == nil ? 0 : DT.Space.dockClearance)

            if let doc = router.opened {
                CardDetailView(document: doc, cards: cards)
                    .zIndex(2)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }

            if let toast = router.toast {
                ToastView(toast: toast) {
                    toast.undo?()
                    router.toast = nil
                }
                .padding(.horizontal, DT.Space.gutter)
                .padding(.bottom, router.opened == nil ? DT.Space.xxl * 2 : DT.Space.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                .zIndex(3)
            }
        }
        .foregroundStyle(DT.Palette.textPrimary)
        .animation(.spring(duration: 0.45, bounce: 0.3), value: router.toast)
        .animation(.snappy(duration: 0.3), value: router.tab)
        .environment(router)
        .sheet(item: $router.editor) { request in
            DocumentEditView(request: request)
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
            router.tab = .home
            router.open(doc)
        }
    }
}

// MARK: - Dok na dole

/// Pływający dok: cztery zakładki i mosiężny plus pośrodku.
struct Dock: View {
    @Binding var selection: AppTab
    var onAdd: () -> Void
    @Namespace private var pill

    var body: some View {
        HStack(spacing: DT.Space.xxs) {
            item(.home)
            item(.calendar)
            addButton
            item(.reminders)
            item(.settings)
        }
        .padding(DT.Space.xs)
        .dockBackground()
    }

    private func item(_ tab: AppTab) -> some View {
        let isOn = selection == tab
        return Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { selection = tab }
        } label: {
            Image(systemName: tab.symbol)
                .symbolVariant(isOn ? .fill : .none)
                .font(DT.Typography.title3)
                .symbolEffect(.bounce, value: isOn)
                .foregroundStyle(isOn ? DT.Palette.textPrimary : DT.Palette.textTertiary)
                .frame(width: DT.Size.dockItem.width, height: DT.Size.dockItem.height)
                .background {
                    if isOn {
                        Capsule()
                            .fill(DT.Palette.surfaceRaised)
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(DT.Typography.title2)
                .foregroundStyle(DT.Palette.onAccent)
                .frame(width: DT.Size.dockPlus, height: DT.Size.dockPlus)
                .background(DT.Palette.accent, in: Circle())
                .shadow(color: DT.Palette.accent.opacity(0.35), radius: DT.Space.sm, y: DT.Space.xxs)
        }
        .buttonStyle(CardPressStyle())
        .padding(.horizontal, DT.Space.xxs)
        .accessibilityLabel("Dodaj dokument")
    }
}

private struct DockBackground: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(DT.Palette.backgroundDeep.opacity(0.55)), in: Capsule())
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .background(DT.Palette.backgroundDeep.opacity(0.6), in: Capsule())
            .overlay(Capsule().strokeBorder(DT.Palette.separator, lineWidth: DT.Size.hairline))
            .shadow(color: DT.Palette.shadow, radius: DT.Space.lg, y: DT.Space.md)
    }
}

extension View {
    func dockBackground() -> some View { modifier(DockBackground()) }
}

/// Komunikat nad dokiem.
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
                Button("Cofnij", action: onUndo)
                    .font(DT.Typography.subheadlineEmphasized)
                    .foregroundStyle(DT.Palette.accentText)
                    .frame(minHeight: DT.Size.touch)
            }
        }
        .padding(.leading, DT.Space.md)
        .padding(.trailing, toast.undo == nil ? DT.Space.md : DT.Space.sm)
        .frame(minHeight: DT.Size.row)
        .dockBackground()
        .accessibilityElement(children: .contain)
    }
}
