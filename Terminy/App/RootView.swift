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
            }
        }
        .tint(Palette.tint)
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .animation(.easeInOut(duration: 0.2), value: lock.isUnlocked)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background:
                lock.lock()
                cameFromBackground = true
            case .active:
                let shouldPrompt = cameFromBackground
                cameFromBackground = false
                guard !TerminyApp.isDemo else { return }
                Task {
                    if shouldPrompt { await lock.unlock() }
                    await NotificationScheduler.shared.requestAuthorization()
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

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                Text("Terminy są zablokowane")
                    .font(.title2.weight(.bold))
                if let error = lock.lastError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Odblokuj", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 12)
                }
                .controlSize(.large)
                .primaryButton()
                .padding(.top, 10)
            }
            .padding(24)
        }
    }
}
