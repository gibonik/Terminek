import Foundation

/// Co widzi widżet: najbliższe terminy (nazwa, rodzaj, data). Bez numerów, właścicieli i skanów.
/// Aplikacja zapisuje to do wspólnego katalogu grupy, a widżet tylko czyta.
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
        var categoryRaw: String
        var expiryDate: Date
    }

    var items: [Item]
    var updated: Date

    static let groupID = "group.pl.terminy.app"
    static let widgetKind = "TerminekNextDeadline"
    private static let fileName = "widget.json"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }

    /// Czy grupa aplikacji działa (przy instalacji z darmowego Apple ID bywa niedostępna).
    static var isAvailable: Bool { fileURL != nil }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        // Widżet musi czytać plik także przy zablokowanym telefonie (odświeżanie o północy).
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Dokumenty od najbliższego: najpierw te po terminie, potem przyszłe.
    func upcoming(now: Date = .now, calendar: Calendar = .current) -> [Item] {
        let today = calendar.startOfDay(for: now)
        let expired = items.filter { calendar.startOfDay(for: $0.expiryDate) < today }.sorted { $0.expiryDate > $1.expiryDate }
        let future = items.filter { calendar.startOfDay(for: $0.expiryDate) >= today }.sorted { $0.expiryDate < $1.expiryDate }
        return expired + future
    }
}
