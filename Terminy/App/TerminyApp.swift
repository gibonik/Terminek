import SwiftUI
import SwiftData

@main
struct TerminyApp: App {
    static let cloudKitContainerID = "iCloud.pl.terminy.app"

    let container: ModelContainer
    @State private var lock = AppLock()

    init() {
        let schema = Schema([Document.self])
        do {
            // Prywatna baza CloudKit: dane widzi tylko właściciel konta iCloud,
            // synchronizują się między jego urządzeniami.
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private(Self.cloudKitContainerID))
            container = try ModelContainer(for: schema, configurations: cloud)
        } catch {
            // Np. brak podpisu/entitlementów w symulatorze – działamy lokalnie.
            print("CloudKit niedostępny, zapis lokalny: \(error)")
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            container = try! ModelContainer(for: schema, configurations: local)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(lock)
        }
        .modelContainer(container)
    }
}
