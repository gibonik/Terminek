import Foundation

/// Rodzaj dokumentu. Zapisywany w modelu jako `String` (rawValue), bo CloudKit
/// nie lubi enumów z wartościami powiązanymi i zmian schematu.
enum DocumentCategory: String, CaseIterable, Identifiable, Codable {
    case carInsurance
    case carInspection
    case passport
    case idCard
    case drivingLicense
    case subscription
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .carInsurance: "Ubezpieczenie OC"
        case .carInspection: "Przegląd techniczny"
        case .passport: "Paszport"
        case .idCard: "Dowód osobisty"
        case .drivingLicense: "Prawo jazdy"
        case .subscription: "Subskrypcja"
        case .other: "Inne"
        }
    }

    var symbol: String {
        switch self {
        case .carInsurance: "car.side"
        case .carInspection: "wrench.and.screwdriver"
        case .passport: "globe.europe.africa"
        case .idCard: "person.text.rectangle"
        case .drivingLicense: "steeringwheel"
        case .subscription: "arrow.triangle.2.circlepath"
        case .other: "doc.text"
        }
    }

    /// Typowy okres ważności po odnowieniu, używany przez przycisk „Odnów”.
    var defaultRenewal: DateComponents {
        switch self {
        case .carInsurance, .carInspection: DateComponents(year: 1)
        case .passport, .idCard: DateComponents(year: 10)
        case .drivingLicense: DateComponents(year: 15)
        case .subscription: DateComponents(month: 1)
        case .other: DateComponents(year: 1)
        }
    }
}

enum BillingCycle: String, CaseIterable, Identifiable, Codable {
    case monthly, quarterly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: "Co miesiąc"
        case .quarterly: "Co kwartał"
        case .yearly: "Co rok"
        }
    }

    var components: DateComponents {
        switch self {
        case .monthly: DateComponents(month: 1)
        case .quarterly: DateComponents(month: 3)
        case .yearly: DateComponents(year: 1)
        }
    }
}
