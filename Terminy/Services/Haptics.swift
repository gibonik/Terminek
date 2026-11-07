import CoreHaptics
import UIKit

/// Wibracje mówią „co się stało”, a nie „jak ma brzęczeć”. Każde zdarzenie ma swój wzór,
/// najrzadsze (odnowienie dokumentu) jest najmocniejsze.
enum HapticEvent {
    /// Karta wysuwa się z portfela.
    case pull
    /// Karta wraca do portfela.
    case stow
    /// Nowy dokument wsuwa się do portfela.
    case insert
    /// Pieczątka „Nieważny” uderza w kartę.
    case stamp
    /// Dokument wyjęty i usunięty.
    case remove
    /// Odnowienie: trzy rosnące stuknięcia i narastający szum.
    case renew
}

@MainActor
final class Haptics {
    static let shared = Haptics()
    static let enabledKey = "hapticsEnabled"

    private var engine: CHHapticEngine?
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func fire(_ event: HapticEvent) {
        guard enabled, supported else { return }
        do {
            let engine = try startedEngine()
            let pattern = try CHHapticPattern(events: Self.events(for: event), parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            self.engine = nil
        }
    }

    private var lastOnce: [String: Date] = [:]

    /// Jak `fire`, ale kilka takich samych zdarzeń naraz (np. pieczątki na kilku kartach) daje jedną wibrację.
    func fireOnce(_ event: HapticEvent) {
        let key = String(describing: event)
        if let last = lastOnce[key], Date.now.timeIntervalSince(last) < 0.6 { return }
        lastOnce[key] = .now
        fire(event)
    }

    /// Silnik zatrzymujemy w tle, a przy następnym `fire` uruchamia się sam.
    func stop() {
        engine?.stop()
        engine = nil
    }

    private func startedEngine() throws -> CHHapticEngine {
        if let engine { return engine }
        let engine = try CHHapticEngine()
        engine.isAutoShutdownEnabled = true
        engine.stoppedHandler = { [weak self] _ in
            Task { @MainActor in self?.engine = nil }
        }
        engine.resetHandler = { [weak self] in
            Task { @MainActor in self?.engine = nil }
        }
        try engine.start()
        self.engine = engine
        return engine
    }

    private static func tap(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time)
    }

    private static func rumble(_ time: TimeInterval, _ duration: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time, duration: duration)
    }

    static func events(for event: HapticEvent) -> [CHHapticEvent] {
        switch event {
        case .pull:
            // Plastik trze o skórę, potem karta „puszcza”.
            [rumble(0, 0.12, 0.25, 0.15), tap(0.12, 0.55, 0.45)]
        case .stow:
            [tap(0, 0.4, 0.3)]
        case .insert:
            [rumble(0, 0.2, 0.3, 0.1), tap(0.22, 0.7, 0.5), tap(0.34, 0.35, 0.3)]
        case .stamp:
            [tap(0, 1.0, 0.2), rumble(0.02, 0.18, 0.45, 0.05)]
        case .remove:
            [tap(0, 0.5, 0.2), tap(0.14, 0.3, 0.15)]
        case .renew:
            [tap(0, 0.45, 0.5), tap(0.12, 0.65, 0.6), tap(0.24, 0.9, 0.75),
             rumble(0.3, 0.45, 0.5, 0.35)]
        }
    }
}
