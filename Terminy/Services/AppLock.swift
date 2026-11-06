import Foundation
import LocalAuthentication
import Observation

/// Blokada aplikacji Face ID / Touch ID (z kodem urządzenia jako zapasem).
@MainActor
@Observable
final class AppLock {
    static let enabledKey = "faceIDEnabled"

    private(set) var isUnlocked = false
    private(set) var lastError: String?

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { isUnlocked = true }
        }
    }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "kod urządzenia"
        }
    }

    init() {
        let enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        isEnabled = enabled
        isUnlocked = !enabled
    }

    func lock() {
        if isEnabled { isUnlocked = false }
    }

    func unlock() async {
        guard isEnabled else { isUnlocked = true; return }
        guard !isUnlocked else { return }

        let context = LAContext()
        context.localizedCancelTitle = "Anuluj"
        var error: NSError?
        // .deviceOwnerAuthentication = biometria, a po porażce kod urządzenia.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Brak zabezpieczeń na urządzeniu (np. symulator bez kodu) – nie blokujemy na zawsze.
            isUnlocked = true
            return
        }
        do {
            isUnlocked = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Odblokuj swoje dokumenty"
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
