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
            DocumentListView()

            if lock.isEnabled && (!lock.isUnlocked || scenePhase != .active) {
                LockView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lock.isUnlocked)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background:
                lock.lock()
                cameFromBackground = true
            case .active:
                let shouldPrompt = cameFromBackground
                cameFromBackground = false
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
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Terminy są zablokowane")
                    .font(.title3.weight(.semibold))
                if let error = lock.lastError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Odblokuj (\(lock.biometryName))", systemImage: "faceid")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
