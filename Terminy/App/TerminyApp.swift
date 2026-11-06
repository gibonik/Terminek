import SwiftUI
import SwiftData

@main
struct TerminyApp: App {
    static let cloudKitContainerID = "iCloud.pl.terminy.app"

    let container: ModelContainer
    @State private var lock = AppLock()

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(lock)
        }
        .modelContainer(container)
    }

    /// Prywatna baza CloudKit, gdy się da (płatne konto deweloperskie + zalogowany iCloud).
    /// W przeciwnym razie zapis lokalny – np. przy instalacji przez Sideloadly na darmowe Apple ID,
    /// które nie dostaje uprawnień iCloud.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Document.self])
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        if isRunningTests {
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }

        if FileManager.default.ubiquityIdentityToken != nil {
            let cloud = ModelConfiguration(
                "Cloud", schema: schema,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            if let container = try? ModelContainer(for: schema, configurations: cloud) {
                return container
            }
        }

        let local = ModelConfiguration("Local", schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: local) {
            return container
        }
        print("Nie udało się otworzyć bazy na dysku, dane tylko w pamięci.")
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
