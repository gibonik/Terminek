import AppIntents
import SwiftUI

// Skróty Siri i aplikacji Skróty. Wszystkie działają na telefonie, bez internetu.
// Te, które czytają dokumenty, wymagają odblokowanego iPhone'a, żeby nikt nie wyciągnął
// terminów z zablokowanego ekranu.

/// „Jaki jest mój najbliższy termin?”
struct NextDeadlineIntent: AppIntent {
    static let title: LocalizedStringResource = "Najbliższy termin"
    static let description = IntentDescription("Mówi, który dokument kończy się najwcześniej.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let docs = IntentData.documents()
        Breadcrumbs.add("Siri: najbliższy termin")
        guard let next = docs.first(where: { $0.daysLeft() >= 0 }) ?? docs.last else {
            return .result(dialog: "Nie masz jeszcze żadnych dokumentów w Terminku.", view: Snippet())
        }
        let expired = docs.filter { $0.daysLeft() < 0 }.count
        var text = Assistant().sentence(for: next)
        if expired > 0 { text += " Po terminie: \(Assistant.documentsCount(expired))." }
        return .result(dialog: IntentDialog(stringLiteral: text), view: Snippet(card: CardData(next)))
    }
}

/// „Kiedy kończy się …?” dla wybranego dokumentu.
struct CheckDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Sprawdź termin dokumentu"
    static let description = IntentDescription("Mówi, do kiedy jest ważny wybrany dokument.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Dokument", requestValueDialog: "Który dokument?")
    var document: DocumentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Sprawdź termin \(\.$document)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let doc = IntentData.document(document.id) else {
            return .result(dialog: "Nie znalazłem tego dokumentu. Może został usunięty.", view: Snippet())
        }
        Breadcrumbs.add("Siri: termin dokumentu")
        return .result(dialog: IntentDialog(stringLiteral: Assistant().sentence(for: doc)), view: Snippet(card: CardData(doc)))
    }
}

/// „Co wygasa w ciągu 30 dni?”
struct ExpiringSoonIntent: AppIntent {
    static let title: LocalizedStringResource = "Co wkrótce wygasa"
    static let description = IntentDescription("Lista dokumentów, które kończą się w wybranym czasie, i tych po terminie.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Dni", default: 30)
    var days: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Co wygasa w ciągu \(\.$days) dni")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView & ReturnsValue<[DocumentEntity]> {
        let days = min(max(self.days, 1), 3650)
        let docs = IntentData.documents()
        let expired = docs.filter { $0.daysLeft() < 0 }
        let soon = docs.filter { (0...days).contains($0.daysLeft()) }
        Breadcrumbs.add("Siri: co wygasa")

        var text: String
        if soon.isEmpty {
            text = "W ciągu \(days) \(DaysText.dni(days)) nic się nie kończy."
        } else {
            text = "W ciągu \(days) \(DaysText.dni(days)) kończy się: \(Assistant.documentsCount(soon.count))."
            if let first = soon.first { text += " Najpierw " + Assistant().sentence(for: first) }
        }
        if !expired.isEmpty { text += " Po terminie: \(Assistant.documentsCount(expired.count))." }

        let shown = Array((expired + soon).prefix(6))
        return .result(value: (expired + soon).map(DocumentEntity.init),
                       dialog: IntentDialog(stringLiteral: text),
                       view: Snippet(rows: shown.map(SnippetRow.init)))
    }
}

/// Pytanie do asystenta, np. „ile płacę za subskrypcje”. Liczy się do darmowego limitu pytań.
struct AskAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Zapytaj asystenta Terminka"
    static let description = IntentDescription("Zadaj pytanie o swoje terminy, np. „co wygasa w marcu?”.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Pytanie", requestValueDialog: "O co chcesz zapytać?")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Zapytaj: \(\.$question)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = Store.shared
        guard store.assistantQuestionsLeft() > 0 else {
            return .result(dialog: "Dziś wykorzystałeś darmowe pytania. Jutro limit się odnowi, a z Terminek Plus pytasz bez ograniczeń.",
                           view: Snippet())
        }
        store.recordAssistantQuestion()
        Breadcrumbs.add("Siri: pytanie do asystenta")
        let docs = IntentData.documents()
        let reply = Assistant().answer(question, documents: docs)
        let rows = reply.documentIDs.compactMap { id in docs.first { $0.id == id } }.prefix(6).map(SnippetRow.init)
        return .result(dialog: IntentDialog(stringLiteral: reply.text), view: Snippet(rows: Array(rows)))
    }
}

/// Odnowienie dokumentu (np. po opłaceniu OC). Pyta o potwierdzenie.
struct RenewDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Odnów dokument"
    static let description = IntentDescription("Przesuwa termin o typowy okres: OC o rok, abonament o cykl płatności.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Dokument", requestValueDialog: "Który dokument odnowić?")
    var document: DocumentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Odnów \(\.$document)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let doc = IntentData.document(document.id) else {
            return .result(dialog: "Nie znalazłem tego dokumentu.")
        }
        let newDate = doc.renewedExpiryDate()
        try await requestConfirmation(
            result: .result(dialog: IntentDialog(stringLiteral: "Odnowić „\(doc.displayTitle)” do \(PL.date(newDate))?"))
        )
        doc.renew()
        await IntentData.saveAndReschedule()
        Breadcrumbs.add("Siri: odnowiono dokument")
        return .result(dialog: IntentDialog(stringLiteral: "Gotowe. „\(doc.displayTitle)” jest ważne do \(PL.date(doc.expiryDate))."))
    }
}

/// Otwiera dokument w aplikacji.
struct OpenDocumentIntent: OpenIntent {
    static let title: LocalizedStringResource = "Otwórz dokument"
    static let description = IntentDescription("Otwiera kartę dokumentu w Terminku.")

    @Parameter(title: "Dokument")
    var target: DocumentEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLink.shared.documentID = target.id
        return .result()
    }
}

// MARK: - Podpowiedzi Siri

/// Gotowe skróty: widać je w aplikacji Skróty i w Spotlight bez żadnej konfiguracji.
///
/// Siri nie mówi po polsku, więc obok polskich fraz są angielskie (gdy Siri jest po angielsku).
/// Po polsku skróty uruchomisz z aplikacji Skróty, Spotlight, przycisku czynności albo stuknięcia w tył.
struct TerminekShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .teal }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextDeadlineIntent(),
            phrases: [
                "Najbliższy termin w \(.applicationName)",
                "Co się kończy w \(.applicationName)",
                "What's my next deadline in \(.applicationName)",
                "Next deadline in \(.applicationName)",
            ],
            shortTitle: "Najbliższy termin",
            systemImageName: "hourglass"
        )
        AppShortcut(
            intent: CheckDocumentIntent(),
            phrases: [
                "Kiedy kończy się \(\.$document) w \(.applicationName)",
                "Sprawdź \(\.$document) w \(.applicationName)",
                "When does \(\.$document) expire in \(.applicationName)",
            ],
            shortTitle: "Termin dokumentu",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: ExpiringSoonIntent(),
            phrases: [
                "Co wygasa w \(.applicationName)",
                "What expires soon in \(.applicationName)",
            ],
            shortTitle: "Co wkrótce wygasa",
            systemImageName: "exclamationmark.triangle"
        )
        AppShortcut(
            intent: RenewDocumentIntent(),
            phrases: [
                "Odnów \(\.$document) w \(.applicationName)",
                "Renew \(\.$document) in \(.applicationName)",
            ],
            shortTitle: "Odnów dokument",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: ScanDocumentIntent(),
            phrases: [
                "Zeskanuj dokument w \(.applicationName)",
                "Scan a document in \(.applicationName)",
            ],
            shortTitle: "Skanuj",
            systemImageName: "doc.viewfinder"
        )
        AppShortcut(
            intent: OpenAssistantIntent(),
            phrases: [
                "Zapytaj \(.applicationName)",
                "Ask \(.applicationName)",
            ],
            shortTitle: "Asystent",
            systemImageName: "sparkles"
        )
    }
}
