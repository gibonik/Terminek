import AppIntents

// Akcje, które otwierają aplikację w konkretnym miejscu. Są w aplikacji i w widżecie,
// bo korzystają z nich też przyciski w Centrum sterowania i przycisk czynności (iOS 18).

struct AddDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Dodaj dokument"
    static let description = IntentDescription("Otwiera Terminka na dodawaniu nowego dokumentu.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        DeepLink.shared.action = .add
        #endif
        return .result()
    }
}

struct ScanDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Zeskanuj dokument"
    static let description = IntentDescription("Otwiera skaner, który odczyta datę ważności.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        DeepLink.shared.action = .scan
        #endif
        return .result()
    }
}

struct OpenAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Otwórz asystenta"
    static let description = IntentDescription("Otwiera czat z asystentem terminów.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        DeepLink.shared.action = .assistant
        #endif
        return .result()
    }
}
