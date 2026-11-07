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

        var planned = Self.plannedReminders(for: documents, hour: reminderHour, now: now,
                                            offsets: Self.enabledOffsets())
        planned += snoozedReminders(for: documents, now: now)
        planned.sort { $0.fireDate < $1.fireDate }

        let calendar = Calendar.current
        for reminder in planned.prefix(maxPending) {
            // Licznik na ikonie w chwili powiadomienia: ile dokumentów będzie wtedy po terminie lub na dziś.
            let fireDay = calendar.startOfDay(for: reminder.fireDate)
            let badge = documents.filter { calendar.startOfDay(for: $0.expiryDate) <= fireDay }.count
            try? await center.add(makeRequest(reminder, badge: badge))
        }
        await updateBadge(documents, now: now)
    }

    /// Licznik na ikonie aplikacji: dokumenty po terminie i te, które kończą się dziś.
    func updateBadge(_ documents: [Document], now: Date = .now) async {
        let count = documents.filter { $0.daysLeft(from: now) <= 0 }.count
        try? await center.setBadgeCount(count)
    }

    /// Próbne powiadomienie za 5 sekund (z przyciskami), żeby zobaczyć, jak wygląda.
    func sendTest(for document: Document?) async {
        guard await requestAuthorization() else { return }
        let content = UNMutableNotificationContent()
        if let document {
            let days = document.daysLeft()
            content.title = document.displayTitle
            content.body = days < 0 ? "Termin minął \(-days) \(DaysText.dni(-days)) temu. Tak będą wyglądać przypomnienia."
                : "Do terminu zostało \(days) \(DaysText.dni(days)). Tak będą wyglądać przypomnienia."
            content.userInfo = [Self.documentIDKey: document.id.uuidString]
            content.categoryIdentifier = Self.categoryID
        } else {
            content.title = "Terminek"
            content.body = "Tak będą wyglądać przypomnienia."
        }
        content.sound = .default
        content.threadIdentifier = "terminy"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    // MARK: Akcje w powiadomieniu

    nonisolated static let categoryID = "deadline"
    nonisolated static let renewAction = "RENEW"
    nonisolated static let snoozeAction = "SNOOZE"
    nonisolated static let documentIDKey = "documentID"
    private let snoozeKey = "snoozedReminders"

    /// Przyciski pod powiadomieniem (przytrzymanie albo rozwinięcie).
    nonisolated static func registerCategories() {
        let renew = UNNotificationAction(identifier: renewAction, title: "Odnów",
                                         options: [], icon: UNNotificationActionIcon(systemImageName: "arrow.clockwise"))
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Przypomnij jutro",
                                          options: [], icon: UNNotificationActionIcon(systemImageName: "clock"))
        let category = UNNotificationCategory(identifier: categoryID, actions: [renew, snooze],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Ponowne przypomnienie jutro o zwykłej godzinie. Zapisane, żeby przetrwało przeliczanie.
    func snooze(_ document: Document, now: Date = .now) {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let fire = calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: tomorrow) else { return }
        var stored = UserDefaults.standard.dictionary(forKey: snoozeKey) as? [String: Double] ?? [:]
        stored[document.id.uuidString] = fire.timeIntervalSince1970
        UserDefaults.standard.set(stored, forKey: snoozeKey)
    }

    private func snoozedReminders(for documents: [Document], now: Date) -> [PlannedReminder] {
        var stored = UserDefaults.standard.dictionary(forKey: snoozeKey) as? [String: Double] ?? [:]
        var result: [PlannedReminder] = []
        for (id, time) in stored {
            let fire = Date(timeIntervalSince1970: time)
            guard fire > now, let doc = documents.first(where: { $0.id.uuidString == id }) else {
                stored[id] = nil
                continue
            }
            let days = doc.daysLeft(from: fire)
            let text = days < 0 ? "Termin minął \(-days) \(days == -1 ? "dzień" : "dni") temu." :
                days == 0 ? "Termin jest dziś." : "Do terminu zostało \(days) \(days == 1 ? "dzień" : "dni")."
            result.append(PlannedReminder(identifier: "\(id)-snooze", fireDate: fire,
                                          title: doc.displayTitle, body: "Przypominam: " + text,
                                          documentID: doc.id))
        }
        UserDefaults.standard.set(stored, forKey: snoozeKey)
        return result
    }

    struct PlannedReminder: Equatable {
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
        var documentID: UUID? = nil
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
            for offset in doc.customOffsets ?? offsets {
                guard
                    let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: doc.expiryDate)),
                    let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                    fire > now
                else { continue }

                result.append(PlannedReminder(
                    identifier: "\(doc.id.uuidString)-\(offset)",
                    fireDate: fire,
                    title: doc.displayTitle,
                    body: body(for: doc, offset: offset),
                    documentID: doc.id
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
            return "Zostało \(offset) \(DaysText.dni(offset))\(who). Termin: \(date)."
        }
    }

    private func makeRequest(_ reminder: PlannedReminder, badge: Int) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.badge = NSNumber(value: badge)
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = "terminy"
        if let id = reminder.documentID {
            content.userInfo = [Self.documentIDKey: id.uuidString]
        }

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }
}
