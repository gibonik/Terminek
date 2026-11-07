import Foundation
import UserNotifications

/// Planuje lokalne przypomnienia: 30 dni, 7 dni przed terminem i w dniu terminu.
///
/// iOS trzyma maksymalnie 64 oczekujące powiadomienia na aplikację, więc przy każdej
/// zmianie przeliczamy wszystko od nowa i zostawiamy tylko najbliższe.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    nonisolated static let reminderOffsets = [30, 7, 0]
    nonisolated static let reminderHourKey = "reminderHour"

    /// Klucz ustawienia „przypominaj X dni przed”.
    nonisolated static func offsetKey(_ offset: Int) -> String { "remind\(offset)" }

    /// Odstępy włączone w ustawieniach (domyślnie wszystkie).
    nonisolated static func enabledOffsets(_ defaults: UserDefaults = .standard) -> [Int] {
        reminderOffsets.filter { defaults.object(forKey: offsetKey($0)) as? Bool ?? true }
    }
    private let maxPending = 60

    private let center = UNUserNotificationCenter.current()

    var reminderHour: Int {
        let stored = UserDefaults.standard.object(forKey: Self.reminderHourKey) as? Int
        return stored ?? 9
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func reschedule(_ documents: [Document], now: Date = .now) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        center.removeAllPendingNotificationRequests()

        let requests = Self.plannedReminders(for: documents, hour: reminderHour, now: now,
                                             offsets: Self.enabledOffsets())
            .prefix(maxPending)
            .map(makeRequest)

        for request in requests {
            try? await center.add(request)
        }
    }

    struct PlannedReminder: Equatable {
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
    }

    /// Czysta funkcja (łatwa do testów): wylicza przyszłe przypomnienia posortowane po dacie.
    nonisolated static func plannedReminders(
        for documents: [Document],
        hour: Int,
        now: Date,
        offsets: [Int] = reminderOffsets,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        for doc in documents where doc.remindersEnabled {
            for offset in offsets {
                guard
                    let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: doc.expiryDate)),
                    let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                    fire > now
                else { continue }

                result.append(PlannedReminder(
                    identifier: "\(doc.id.uuidString)-\(offset)",
                    fireDate: fire,
                    title: doc.displayTitle,
                    body: body(for: doc, offset: offset)
                ))
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }

    nonisolated private static func body(for doc: Document, offset: Int) -> String {
        let who = doc.owner.isEmpty ? "" : " (\(doc.owner))"
        let date = doc.expiryDate.formatted(date: .long, time: .omitted)
        switch offset {
        case 0:
            return doc.category == .subscription
                ? "Dziś odnawia się subskrypcja\(who)."
                : "Dziś kończy się ważność\(who). Termin: \(date)."
        case 7:
            return "Zostało 7 dni\(who). Termin: \(date)."
        default:
            return "Zostało \(offset) dni\(who). Termin: \(date)."
        }
    }

    private func makeRequest(_ reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }
}
