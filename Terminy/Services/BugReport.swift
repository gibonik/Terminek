import UIKit
import SwiftData
import UserNotifications

/// Ostatnie kroki w aplikacji (np. „Skan: 2 str.”, „Odnowiono z powiadomienia”), dołączane do zgłoszenia błędu.
/// Bez danych osobowych: żadnych nazw, numerów ani dat dokumentów. Najwyżej 60 wpisów, tylko na telefonie.
enum Breadcrumbs {
    private static let limit = 60
    private static let queue = DispatchQueue(label: "pl.terminy.breadcrumbs")

    private static var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Diagnostics", isDirectory: true).appendingPathComponent("kroki.log")
    }

    static func add(_ event: String) {
        let line = "\(stamp(.now)) \(event)"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var lines = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
            lines.append(line)
            if lines.count > limit { lines.removeFirst(lines.count - limit) }
            try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }

    static func read() -> String {
        queue.sync { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
    }

    static func clear() {
        queue.sync { try? FileManager.default.removeItem(at: file) }
    }

    private static func stamp(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits).locale(PL.locale))
    }
}

/// Zgłoszenie błędu, pomysłu albo pytania: opis użytkownika + to, co pomaga znaleźć przyczynę.
struct BugReport {
    enum Kind: String, CaseIterable, Identifiable {
        case bug, idea, question
        var id: String { rawValue }

        var title: String {
            switch self {
            case .bug: "Błąd"
            case .idea: "Pomysł"
            case .question: "Pytanie"
            }
        }

        var symbol: String {
            switch self {
            case .bug: "ladybug"
            case .idea: "lightbulb"
            case .question: "questionmark.bubble"
            }
        }

        var prompt: String {
            switch self {
            case .bug: "Co się stało? Co robiłeś tuż przed tym?"
            case .idea: "Czego brakuje w aplikacji?"
            case .question: "O co chcesz zapytać?"
            }
        }
    }

    /// Adres do zgłoszeń. Pusty, dopóki nie podasz swojego (wtedy wiadomość otwiera się bez odbiorcy).
    static let supportEmail = ""

    var kind: Kind
    var message: String
    var includeDevice: Bool
    var includeSteps: Bool
    var screenshot: UIImage?
    var crashReport: URL?

    var subject: String { "Terminek \(Self.version): \(kind.title.lowercased())" }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// Model telefonu, np. „iPhone15,2”.
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Informacje techniczne bez danych dokumentów.
    @MainActor
    static func deviceInfo() async -> String {
        let device = UIDevice.current
        let notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        let count = (try? TerminyApp.sharedContainer?.mainContext.fetchCount(FetchDescriptor<Document>())) ?? 0
        let free = (try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage)
        let store = Store.shared
        let lines = [
            "Wersja: \(version)",
            "System: \(device.systemName) \(device.systemVersion)",
            "Model: \(deviceModel)",
            "Język: \(Locale.preferredLanguages.first ?? "?")",
            "Zapis: \(TerminyApp.usesCloudKit ? "iCloud" : "lokalnie")",
            "Plan: \(store.isPlus ? (store.debugPlus ? "Plus testowy" : "Plus") : "darmowy")",
            "Dokumenty: \(count)",
            "Powiadomienia: \(describe(notifications))",
            "Blokada: \(UserDefaults.standard.object(forKey: AppLock.enabledKey) as? Bool ?? true ? "włączona" : "wyłączona")",
            "Wolne miejsce: \(free.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "?")",
            "Tryb oszczędzania: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "tak" : "nie")",
            "Raporty awarii: \(Diagnostics.shared.reports.count)",
        ]
        return lines.joined(separator: "\n")
    }

    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: "włączone"
        case .denied: "wyłączone"
        case .notDetermined: "nie pytano"
        case .provisional: "ciche"
        case .ephemeral: "tymczasowe"
        @unknown default: "?"
        }
    }

    /// Treść wiadomości.
    @MainActor
    func body() async -> String {
        var parts = [message.trimmingCharacters(in: .whitespacesAndNewlines)]
        if includeDevice {
            parts.append("— Urządzenie —\n" + (await Self.deviceInfo()))
        }
        if includeSteps {
            let steps = Breadcrumbs.read()
            if !steps.isEmpty { parts.append("— Ostatnie kroki —\n" + steps) }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Załączniki: zrzut ekranu i raport awarii.
    func attachments() -> [(data: Data, mime: String, name: String)] {
        var result: [(Data, String, String)] = []
        if let screenshot, let data = screenshot.jpegData(compressionQuality: 0.7) {
            result.append((data, "image/jpeg", "zrzut.jpg"))
        }
        if let crashReport, let data = try? Data(contentsOf: crashReport) {
            result.append((data, "application/json", crashReport.lastPathComponent))
        }
        return result
    }

    /// Pliki do udostępnienia, gdy na telefonie nie ma skonfigurowanej Poczty.
    /// Trafiają do katalogu tymczasowego i są sprzątane po wysłaniu.
    @MainActor
    func shareItems() async -> [Any] {
        var items: [Any] = [subject + "\n\n" + (await body())]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Zgloszenie", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in attachments() {
            let url = folder.appendingPathComponent(item.name)
            if (try? item.data.write(to: url, options: [.atomic, .completeFileProtection])) != nil { items.append(url) }
        }
        return items
    }

    static func cleanUpSharedFiles() {
        let tmp = FileManager.default.temporaryDirectory
        try? FileManager.default.removeItem(at: tmp.appendingPathComponent("Zgloszenie", isDirectory: true))
    }
}

/// Zrzut tego, co jest teraz na ekranie (do zgłoszenia po potrząśnięciu).
@MainActor
enum ScreenCapture {
    static func current() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: \.isKeyWindow) else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
    }
}

// MARK: - Potrząśnięcie

extension Notification.Name {
    static let deviceDidShake = Notification.Name("TerminekDeviceDidShake")
}

extension UIWindow {
    /// Potrząśnięcie telefonem otwiera zgłoszenie błędu (można wyłączyć w Koncie).
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}
