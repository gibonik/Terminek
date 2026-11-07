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
        .tint(Palette.accent)
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
            Palette.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Palette.accentInk)
                    .frame(width: 84, height: 84)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                Text("Terminy są zablokowane")
                    .font(.system(size: 22, weight: .heavy)).tracking(-0.5)
                    .foregroundStyle(Palette.ink)
                if let error = lock.lastError {
                    Text(error)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Odblokuj (\(lock.biometryName))", systemImage: "faceid")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Palette.bg)
                        .padding(.horizontal, 22)
                        .frame(height: 52)
                        .background(Palette.ink, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
            }
            .padding(24)
        }
    }
}
