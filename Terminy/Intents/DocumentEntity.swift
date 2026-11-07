import AppIntents
import SwiftData
import Foundation

/// Dokument widziany przez Siri, Skróty i Spotlight. Tylko to, co potrzebne do odpowiedzi:
/// nazwa, rodzaj, termin i właściciel. Numer dokumentu i skany nie wychodzą poza aplikację.
struct DocumentEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Dokument")
    static let defaultQuery = DocumentQuery()

    let id: UUID
    let title: String
    let categoryTitle: String
    let symbol: String
    let owner: String
    let expiryDate: Date
    let daysLeft: Int

    init(_ document: Document) {
        id = document.id
        title = document.displayTitle
        categoryTitle = document.category.title
        symbol = document.category.symbol
        owner = document.owner
        expiryDate = document.expiryDate
        daysLeft = document.daysLeft()
    }

    var displayRepresentation: DisplayRepresentation {
        let who = owner.isEmpty ? "" : " · \(owner)"
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(DaysText.sentence(daysLeft).capitalizedFirst), \(PL.date(expiryDate))\(who)",
            image: .init(systemName: symbol)
        )
    }
}

/// Wyszukiwanie dokumentów dla Siri i Skrótów (po nazwie, rodzaju i właścicielu).
struct DocumentQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [DocumentEntity] {
        IntentData.documents().filter { identifiers.contains($0.id) }.map(DocumentEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [DocumentEntity] {
        let q = Assistant.fold(string)
        return IntentData.documents()
            .filter { doc in
                [doc.displayTitle, doc.category.title, doc.owner].contains { Assistant.fold($0).contains(q) }
            }
            .map(DocumentEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [DocumentEntity] {
        IntentData.documents().map(DocumentEntity.init)
    }
}

/// Dostęp do bazy z poziomu skrótów (działają także, gdy aplikacja nie ma otwartych widoków).
@MainActor
enum IntentData {
    static var context: ModelContext? { TerminyApp.sharedContainer?.mainContext }

    static func documents() -> [Document] {
        let descriptor = FetchDescriptor<Document>(sortBy: [SortDescriptor(\.expiryDate)])
        return (try? context?.fetch(descriptor)) ?? []
    }

    static func document(_ id: UUID) -> Document? {
        documents().first { $0.id == id }
    }

    /// Po zmianie z poziomu skrótu przeliczamy przypomnienia.
    static func saveAndReschedule() async {
        try? context?.save()
        await NotificationScheduler.shared.reschedule(documents())
    }
}
