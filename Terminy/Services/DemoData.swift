import Foundation
import SwiftData

/// Przykładowe dokumenty do trybu pokazowego (`-demoData`), np. do zrzutów ekranu w CI.
enum DemoData {
    @MainActor
    static func insert(into context: ModelContext, now: Date = .now) {
        let cal = Calendar.current
        func doc(_ title: String, _ category: DocumentCategory, days: Int,
                 owner: String = "", number: String = "", price: Double? = nil) -> Document {
            let date = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now)) ?? now
            let d = Document(title: title, category: category, expiryDate: date, owner: owner, number: number)
            if let price {
                d.price = price
                d.billingCycle = .monthly
            }
            return d
        }
        let docs = [
            doc("Polisa mieszkania", .homeInsurance, days: -2, owner: "Warta"),
            doc("OC Passat", .carInsurance, days: 6, owner: "PZU", number: "WX 12345"),
            doc("Netflix", .subscription, days: 12, price: 67),
            doc("Przegląd Passat", .carInspection, days: 24, number: "WX 12345"),
            doc("Spotify", .subscription, days: 27, price: 23.99),
            doc("Dowód osobisty", .idCard, days: 127, owner: "Ania"),
            doc("Paszport", .passport, days: 1549, owner: "Ja"),
            doc("Prawo jazdy", .drivingLicense, days: 2480, owner: "Ja"),
        ]
        for d in docs { context.insert(d) }
    }
}
