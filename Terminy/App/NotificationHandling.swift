import SwiftUI
import SwiftData
import UserNotifications

/// Co otworzyć z zewnątrz: dokument z powiadomienia albo skrótu Siri, albo akcję ze skrótu.
@MainActor
@Observable
final class DeepLink {
    static let shared = DeepLink()
    var documentID: UUID?
    var action: Action?

    enum Action: String {
        case add, scan, assistant, report
    }
}

/// Odbiera powiadomienia: pokazuje je także przy otwartej aplikacji i obsługuje przyciski
/// „Odnów” i „Przypomnij jutro” bez otwierania aplikacji.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationScheduler.registerCategories()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let idString = response.notification.request.content.userInfo[NotificationScheduler.documentIDKey] as? String
        guard let idString, let id = UUID(uuidString: idString) else { return }
        await NotificationActions.handle(action, documentID: id)
    }
}

@MainActor
enum NotificationActions {
    static func handle(_ action: String, documentID: UUID) async {
        guard let container = TerminyApp.sharedContainer else { return }
        let context = container.mainContext
        let target = documentID
        let descriptor = FetchDescriptor<Document>(predicate: #Predicate { $0.id == target })
        guard let doc = try? context.fetch(descriptor).first else { return }

        switch action {
        case NotificationScheduler.renewAction:
            doc.renew()
            try? context.save()
            Breadcrumbs.add("Odnowiono z powiadomienia")
        case NotificationScheduler.snoozeAction:
            NotificationScheduler.shared.snooze(doc)
        default:
            DeepLink.shared.documentID = documentID
            return
        }
        let all = (try? context.fetch(FetchDescriptor<Document>())) ?? []
        await NotificationScheduler.shared.reschedule(all)
    }
}
