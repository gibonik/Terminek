import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @Query private var documents: [Document]
    /// Automatyczny monit Face ID tylko po powrocie z tła. Samo okno Face ID przełącza
    /// scenę w .inactive → .active, więc bez tej flagi anulowanie zapętliłoby monit.
    @State private var cameFromBackground = true

    var body: some View {
        ZStack {
            MainTabView()

            if lock.isEnabled && (!lock.isUnlocked || scenePhase != .active) {
                LockView()
                    .transition(.opacity)
            }
        }
        .tint(Palette.tint)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: lock.isUnlocked)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background:
                lock.lock()
                Haptics.shared.stop()
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
        .onChange(of: reminderSignature) {
            Task { await NotificationScheduler.shared.reschedule(documents) }
        }
    }

    private var reminderSignature: String {
        documents
            .map { "\($0.id)|\($0.expiryDate.timeIntervalSince1970)|\($0.remindersEnabled)|\($0.title)|\($0.owner)" }
            .sorted()
            .joined(separator: ";")
    }
}

struct LockView: View {
    @Environment(AppLock.self) private var lock
    @State private var pulse = false

    var body: some View {
        ZStack {
            WalletBackground()
            VStack(spacing: 16) {
                ZStack {
                    Circle().strokeBorder(W.gold.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulse ? 1.15 : 0.95)
                        .opacity(pulse ? 0 : 1)
                    Circle().fill(W.gold).frame(width: 92, height: 92)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(W.goldInk)
                }
                .padding(.bottom, 8)
                Text("Portfel zamknięty")
                    .font(.brico(28, .heavy, relativeTo: .title))
                    .foregroundStyle(W.cream)
                if let error = lock.lastError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(W.muted)
                        .multilineTextAlignment(.center)
                }
                GoldButton(title: "Otwórz (\(lock.biometryName))", symbol: "faceid") {
                    Task { await lock.unlock() }
                }
                .padding(.top, 14)
                .padding(.horizontal, 40)
            }
            .padding(24)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
