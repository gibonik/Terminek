import Foundation
import WidgetKit

/// Przekazuje widżetowi najbliższe terminy (tylko nazwa, rodzaj i data).
@MainActor
enum WidgetSync {
    private static var last: [WidgetSnapshot.Item] = []

    static func update(_ documents: [Document]) {
        guard WidgetSnapshot.isAvailable else { return }
        let items = documents.sorted { $0.expiryDate < $1.expiryDate }.prefix(20).map {
            WidgetSnapshot.Item(id: $0.id, title: $0.displayTitle, categoryRaw: $0.categoryRaw, expiryDate: $0.expiryDate)
        }
        guard Array(items) != last else { return }
        last = Array(items)
        WidgetSnapshot(items: Array(items), updated: .now).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
