import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @Query private var documents: [Document]
    /// Automatyczny monit Face ID tylko po powrocie z tła. Samo okno Face ID przełącza
    /// scenę w .inactive → .active, więc bez tej flagi anulowanie zapętliłoby monit.
    @State private var cameFromBackground = true
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        ZStack {
            MainTabView()

            if lock.isEnabled && (!lock.isUnlocked || scenePhase != .active) {
                LockView()
                    .transition(.opacity)
            } else if scenePhase != .active && !TerminyApp.isDemo {
                // Podgląd w przełączniku aplikacji nie pokazuje numerów ani skanów.
                PrivacyCover()
                    .transition(.opacity)
            }
        }
        .tint(DT.Palette.accent)
        // Zasłona także nad otwartymi arkuszami (szczegóły, edytor), których ZStack nie przykrywa.
        .onChange(of: shield, initial: true) { _, kind in
            ShieldWindow.shared.update(kind, lock: lock, style: AppAppearance(rawValue: appearance)?.colorScheme)
        }
        .task { Store.shared.start() }
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .animation(.easeInOut(duration: 0.2), value: lock.isUnlocked)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background:
                lock.lock()
                Haptics.shared.stop()
                ScanStore.protectScanFiles()
                cameFromBackground = true
            case .active:
                let shouldPrompt = cameFromBackground
                cameFromBackground = false
                guard !TerminyApp.isDemo else { return }
                Task {
                    if shouldPrompt { await lock.unlock() }
                    // Pierwsze pytanie o powiadomienia dopiero po dodaniu dokumentu (w edytorze).
                    if !documents.isEmpty { await NotificationScheduler.shared.requestAuthorization() }
                    await NotificationScheduler.shared.reschedule(documents)
                }
            default:
                break
            }
        }
        // Każda zmiana (także ta, która przyszła z iCloud z innego urządzenia) przelicza przypomnienia.
        .onChange(of: reminderSignature, initial: true) { old, new in
            WidgetSync.update(documents)
            guard old != new else { return }
            Task { await NotificationScheduler.shared.reschedule(documents) }
        }
    }

    private var shield: ShieldWindow.Kind? {
        if lock.isEnabled && (!lock.isUnlocked || scenePhase != .active) { return .lock }
        if scenePhase != .active && !TerminyApp.isDemo { return .privacy }
        return nil
    }

    private var reminderSignature: String {
        documents
            .map { "\($0.id)|\($0.expiryDate.timeIntervalSince1970)|\($0.remindersEnabled)|\($0.title)|\($0.owner)|\($0.customOffsetsRaw)|\($0.categoryRaw)" }
            .sorted()
            .joined(separator: ";")
    }
}

struct LockView: View {
    @Environment(AppLock.self) private var lock
    @State private var pulse = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: DT.Space.md) {
                ZStack {
                    Circle().strokeBorder(DT.Palette.accent.opacity(0.35), lineWidth: DT.Size.hairline * 2)
                        .frame(width: DT.Size.lockHalo, height: DT.Size.lockHalo)
                        .scaleEffect(pulse ? 1.15 : 0.95)
                        .opacity(pulse ? 0 : 1)
                    LogoMark(size: DT.Size.lockBadge)
                }
                .padding(.bottom, DT.Space.xs)
                Text("Terminek jest zablokowany")
                    .font(DT.Typography.title)
                    .foregroundStyle(DT.Palette.textPrimary)
                if let error = lock.lastError {
                    Text(error)
                        .font(DT.Typography.subheadline)
                        .foregroundStyle(DT.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                PrimaryButton(title: "Otwórz (\(lock.biometryName))", symbol: "faceid") {
                    Task { await lock.unlock() }
                }
                .padding(.top, DT.Space.md)
                .padding(.horizontal, DT.Space.xxl)
            }
            .padding(DT.Space.lg)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Osobne okno nad całą aplikacją (także nad arkuszami) z blokadą albo zasłoną prywatności.
@MainActor
final class ShieldWindow {
    static let shared = ShieldWindow()
    enum Kind: Equatable { case lock, privacy }

    private var window: UIWindow?
    private var host: UIHostingController<AnyView>?

    func update(_ kind: Kind?, lock: AppLock, style: ColorScheme?) {
        guard let kind else { hide(); return }
        let root = AnyView(Group {
            switch kind {
            case .lock: LockView().environment(lock)
            case .privacy: PrivacyCover()
            }
        }.tint(DT.Palette.accent))

        if let window, let host {
            host.rootView = root
            window.overrideUserInterfaceStyle = Self.uiStyle(style)
            window.alpha = 1
            window.isHidden = false
            return
        }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = Self.uiStyle(style)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.accessibilityViewIsModal = true
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        self.host = host
    }

    private func hide() {
        guard let window, !window.isHidden else { return }
        UIView.animate(withDuration: 0.2, animations: { window.alpha = 0 }) { _ in
            if window.alpha == 0 { window.isHidden = true }
        }
    }

    private static func uiStyle(_ scheme: ColorScheme?) -> UIUserInterfaceStyle {
        switch scheme {
        case .light: .light
        case .dark: .dark
        default: .unspecified
        }
    }
}

/// Zasłona na czas, gdy aplikacja nie jest na wierzchu (przełącznik aplikacji, Centrum sterowania).
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            DT.Palette.background.opacity(0.6).ignoresSafeArea()
            LogoMark(size: DT.Size.lockBadge)
        }
        .accessibilityHidden(true)
    }
}
