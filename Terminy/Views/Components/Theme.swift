import SwiftUI

/// Kolory pilności: czerwony (po terminie), pomarańczowy (≤ 7 dni), żółty (≤ 30 dni), zielony.
enum Urgency {
    case expired, critical, soon, ok

    init(daysLeft: Int) {
        switch daysLeft {
        case ..<0: self = .expired
        case 0...7: self = .critical
        case 8...30: self = .soon
        default: self = .ok
        }
    }

    var color: Color {
        switch self {
        case .expired: Color(red: 0.90, green: 0.22, blue: 0.23)
        case .critical: Color(red: 0.96, green: 0.45, blue: 0.10)
        case .soon: Color(red: 0.93, green: 0.69, blue: 0.05)
        case .ok: Color(red: 0.17, green: 0.62, blue: 0.33)
        }
    }

    var gradient: LinearGradient {
        let colors: [Color] = switch self {
        case .expired: [Color(red: 0.93, green: 0.28, blue: 0.30), Color(red: 0.62, green: 0.08, blue: 0.20)]
        case .critical: [Color(red: 1.00, green: 0.58, blue: 0.20), Color(red: 0.85, green: 0.27, blue: 0.08)]
        case .soon: [Color(red: 0.98, green: 0.78, blue: 0.20), Color(red: 0.88, green: 0.50, blue: 0.05)]
        case .ok: [Color(red: 0.25, green: 0.75, blue: 0.48), Color(red: 0.07, green: 0.45, blue: 0.36)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Document {
    var urgency: Urgency { Urgency(daysLeft: daysLeft()) }

    /// Koszt miesięczny subskrypcji (do statystyk na pulpicie).
    var monthlyCost: Double {
        guard category == .subscription, let price else { return 0 }
        switch billingCycle ?? .monthly {
        case .monthly: return price
        case .quarterly: return price / 3
        case .yearly: return price / 12
        }
    }
}

/// „6 dni”, „jutro”, „2 dni po”, „4 lata”.
enum DaysText {
    static func short(_ days: Int) -> String {
        switch days {
        case ..<0: return "\(-days) \(dni(-days)) po"
        case 0: return "dziś"
        case 1: return "jutro"
        case 2...365: return "\(days) \(dni(days))"
        default:
            let years = days / 365
            return "\(years) \(lata(years))"
        }
    }

    /// Liczba i jednostka osobno, do dużego licznika.
    static func split(_ days: Int) -> (value: String, unit: String) {
        switch days {
        case ..<0: return ("\(-days)", "\(dni(-days)) po terminie")
        case 0: return ("0", "dni · to dziś")
        case 1...365: return ("\(days)", dni(days))
        default:
            let years = days / 365
            return ("\(years)", lata(years))
        }
    }

    static func dni(_ n: Int) -> String { n == 1 ? "dzień" : "dni" }

    static func lata(_ n: Int) -> String {
        if n == 1 { return "rok" }
        let tens = n % 100, ones = n % 10
        return (2...4).contains(ones) && !(12...14).contains(tens) ? "lata" : "lat"
    }
}

struct DaysLeftBadge: View {
    let daysLeft: Int

    var body: some View {
        let color = Urgency(daysLeft: daysLeft).color
        Text(DaysText.short(daysLeft))
            .font(.caption.weight(.bold).monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .contentTransition(.numericText())
    }
}

/// Wiersz z kolorowym paskiem pilności po lewej i dużą liczbą dni po prawej.
struct StripeRow: View {
    let document: Document

    var body: some View {
        let days = document.daysLeft()
        let urgency = Urgency(daysLeft: days)
        let split = DaysText.split(days)

        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(urgency.color)
                .frame(width: 5)
                .padding(.vertical, 2)

            Image(systemName: document.category.symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(urgency.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(urgency.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.displayTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 0) {
                Text(days < 0 ? "−\(split.value)" : split.value)
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .contentTransition(.numericText())
                Text(days < 0 ? "po" : split.unit)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(urgency.color)
        }
        .frame(minHeight: 44)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !document.owner.isEmpty { parts.append(document.owner) }
        parts.append(document.expiryDate.formatted(.dateTime.day().month(.abbreviated).year()))
        if document.category == .subscription, let price = document.price {
            parts.append(price.formatted(.currency(code: "PLN").precision(.fractionLength(0...2))))
        }
        return parts.joined(separator: " · ")
    }
}

/// Pierścień postępu: ile z ostatnich 30 dni przed terminem już minęło.
struct CountdownRing: View {
    let daysLeft: Int
    var lineWidth: CGFloat = 8
    @State private var animatedProgress: Double = 0

    private var progress: Double {
        if daysLeft <= 0 { return 1 }
        return 1 - min(Double(daysLeft), 30) / 30
    }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            withAnimation(.spring(duration: 1.2, bounce: 0.3).delay(0.15)) { animatedProgress = progress }
        }
        .onChange(of: daysLeft) {
            withAnimation(.spring(duration: 0.8)) { animatedProgress = progress }
        }
    }
}
