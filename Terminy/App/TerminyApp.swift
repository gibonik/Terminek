import SwiftUI
import SwiftData

@main
struct TerminyApp: App {
    static let cloudKitContainerID = "iCloud.pl.terminy.app"
    /// Czy baza faktycznie działa na iCloud (ustawiane przy starcie).
    static var usesCloudKit = false
    /// Tryb pokazowy z przykładowymi danymi (zrzuty ekranu w CI): `-demoData`.
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demoData")

    /// Jedna baza dla całej aplikacji: widoków, akcji z powiadomień i skrótów Siri.
    /// Skróty potrafią uruchomić aplikację w tle bez widoków, dlatego baza tworzy się przy pierwszym użyciu.
    @MainActor static let model: ModelContainer = makeContainer()
    @MainActor static var sharedContainer: ModelContainer? { model }

    let container: ModelContainer
    @State private var lock = AppLock()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        container = Self.model
        Diagnostics.shared.start()
        Breadcrumbs.add("Start aplikacji")
        ScanStore.removeSharedFiles()
        TerminekShortcuts.updateAppShortcutParameters()
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
    /// Czy aplikacja faktycznie ma uprawnienie CloudKit. Próba otwarcia bazy CloudKit bez niego
    /// potrafi zabić aplikację od razu przy starcie (zamiast rzucić błąd), więc sprawdzamy to wcześniej.
    ///
    /// - Sideloadly / darmowe Apple ID: w `embedded.mobileprovision` nie ma CloudKit → zapis lokalny.
    /// - Build deweloperski z płatnego konta: profil zawiera CloudKit → iCloud.
    /// - App Store / TestFlight: profilu nie ma w paczce, uprawnienia nadał Apple → iCloud.
    static var canUseCloudKit: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-forceCloudKit") { return true }   // tylko do testów w CI
        if args.contains("-disableCloudKit") { return false }
        #if targetEnvironment(simulator)
        return false
        #else
        guard FileManager.default.ubiquityIdentityToken != nil else { return false }
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            return true
        }
        guard let data = try? Data(contentsOf: url) else { return false }
        // Profil to podpisany plist; wystarczy poszukać w nim klucza usług iCloud.
        let text = String(decoding: data, as: UTF8.self)
        return text.contains("com.apple.developer.icloud-services") && text.contains("CloudKit")
        #endif
    }

    @MainActor private static func makeContainer() -> ModelContainer {
        let schema = Schema([Document.self])
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        if isDemo {
            let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            DemoData.insert(into: container.mainContext)
            return container
        }

        if isRunningTests {
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }

        if canUseCloudKit {
            let cloud = ModelConfiguration(
                "Cloud", schema: schema,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            if let container = try? ModelContainer(for: schema, configurations: cloud) {
                usesCloudKit = true
                return container
            }
        }

        let local = ModelConfiguration("Local", schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: local) {
            return container
        }
        Log.store.error("Nie udało się otworzyć bazy na dysku, dane tylko w pamięci.")
        Breadcrumbs.add("Błąd: baza tylko w pamięci")
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
