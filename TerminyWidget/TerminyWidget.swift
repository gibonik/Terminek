import WidgetKit
import SwiftUI
import AppIntents

@main
struct TerminekWidgets: WidgetBundle {
    var body: some Widget {
        NextDeadlineWidget()
        if #available(iOS 18.0, *) {
            ScanControl()
            AddControl()
        }
    }
}

// MARK: - Dane

struct DeadlineEntry: TimelineEntry {
    let date: Date
    /// `nil` = widżet nie ma dostępu do danych aplikacji.
    let items: [WidgetSnapshot.Item]?
}

struct DeadlineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeadlineEntry {
        DeadlineEntry(date: .now, items: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DeadlineEntry) -> Void) {
        let items = WidgetSnapshot.load()?.upcoming()
        completion(DeadlineEntry(date: .now, items: context.isPreview && (items ?? []).isEmpty ? Self.sample : items))
    }

    /// Liczba dni zmienia się o północy, więc wpis na każdy z najbliższych 7 dni.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlineEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var entries = [DeadlineEntry(date: .now, items: snapshot?.upcoming(now: .now))]
        for day in 1...7 {
            guard let date = cal.date(byAdding: .day, value: day, to: today) else { continue }
            entries.append(DeadlineEntry(date: date, items: snapshot?.upcoming(now: date)))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static let sample: [WidgetSnapshot.Item] = {
        let cal = Calendar.current
        func item(_ title: String, _ category: DocumentCategory, _ days: Int) -> WidgetSnapshot.Item {
            WidgetSnapshot.Item(id: UUID(), title: title, categoryRaw: category.rawValue,
                                expiryDate: cal.date(byAdding: .day, value: days, to: .now) ?? .now)
        }
        return [item("OC Passat", .carInsurance, 6), item("Netflix", .subscription, 12), item("Przegląd Passat", .carInspection, 24)]
    }()
}

// MARK: - Widżet

struct NextDeadlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: DeadlineProvider()) { entry in
            DeadlineWidgetView(entry: entry)
        }
        .configurationDisplayName("Najbliższy termin")
        .description("Ile dni zostało do najbliższego terminu.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct DeadlineWidgetView: View {
    let entry: DeadlineEntry
    @Environment(\.widgetFamily) private var family

    private var next: WidgetSnapshot.Item? {
        guard let items = entry.items else { return nil }
        let today = Calendar.current.startOfDay(for: entry.date)
        return items.first { Calendar.current.startOfDay(for: $0.expiryDate) >= today } ?? items.first
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(next.flatMap { URL(string: "terminek://document/\($0.id.uuidString)") })
    }

    private func days(_ item: WidgetSnapshot.Item) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: entry.date), to: cal.startOfDay(for: item.expiryDate)).day ?? 0
    }

    private func category(_ item: WidgetSnapshot.Item) -> DocumentCategory {
        DocumentCategory(rawValue: item.categoryRaw) ?? .other
    }

    /// („6”, „dni”), („Dziś”, nil), („3”, „dni po”).
    private func count(_ item: WidgetSnapshot.Item) -> (value: String, unit: String?) {
        let d = days(item)
        if d == 0 { return ("Dziś", nil) }
        if d == 1 { return ("1", "dzień") }
        if abs(d) <= 99 { return ("\(abs(d))", d < 0 ? "dni po" : "dni") }
        return (DaysText.compact(to: item.expiryDate, from: entry.date), nil)
    }

    // MARK: Ekran główny

    @ViewBuilder
    private var small: some View {
        if let next {
            smallContent(next)
                .containerBackground(for: .widget) { gradient(category(next), expired: days(next) < 0) }
        } else {
            empty
        }
    }

    private func smallContent(_ next: WidgetSnapshot.Item) -> some View {
        let cat = category(next)
        let c = count(next)
        return VStack(alignment: .leading, spacing: DT.Space.xxs) {
                HStack {
                    Image(systemName: cat.symbol).font(DT.Typography.subheadlineEmphasized)
                    Spacer()
                    Text(days(next) < 0 ? "PO TERMINIE" : "NAJBLIŻSZY")
                        .font(DT.Typography.overline)
                        .opacity(0.8)
                }
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: DT.Space.xxs) {
                    Text(c.value)
                        .font(DT.Typography.cardNumber)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if let unit = c.unit { Text(unit).font(DT.Typography.footnoteEmphasized).opacity(0.85) }
                }
                Text(next.title)
                    .font(DT.Typography.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
                Text(PL.numeric(next.expiryDate))
                    .font(DT.Typography.caption)
                    .monospacedDigit()
                    .opacity(0.8)
            }
            .foregroundStyle(cat.cardInk)
            .padding(DT.Space.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var medium: some View {
        if let items = entry.items, let next {
            let rest = items.filter { $0.id != next.id }.prefix(3)
            HStack(spacing: 0) {
                smallContent(next)
                    .background(gradient(category(next), expired: days(next) < 0))
                VStack(alignment: .leading, spacing: DT.Space.xs) {
                    Text("DALEJ")
                        .font(DT.Typography.overline)
                        .foregroundStyle(DT.Palette.textSecondary)
                    if rest.isEmpty {
                        Text("Nic więcej w kolejce.")
                            .font(DT.Typography.footnote)
                            .foregroundStyle(DT.Palette.textSecondary)
                    }
                    ForEach(Array(rest)) { item in
                        Link(destination: URL(string: "terminek://document/\(item.id.uuidString)")!) {
                            HStack(spacing: DT.Space.xs) {
                                Circle().fill(category(item).cardGlow).frame(width: DT.Space.xs, height: DT.Space.xs)
                                Text(item.title)
                                    .font(DT.Typography.footnoteEmphasized)
                                    .foregroundStyle(DT.Palette.textPrimary)
                                    .lineLimit(1)
                                    .privacySensitive()
                                Spacer(minLength: DT.Space.xxs)
                                Text(DaysText.short(days(item)))
                                    .font(DT.Typography.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(days(item) < 0 ? DT.Palette.danger : days(item) <= 7 ? DT.Palette.warning : DT.Palette.textSecondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(DT.Space.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .containerBackground(for: .widget) { DT.Palette.backgroundElevated }
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: DT.Space.xs) {
            Image(systemName: entry.items == nil ? "exclamationmark.arrow.triangle.2.circlepath" : "plus.circle.fill")
                .font(DT.Typography.title2)
                .foregroundStyle(DT.Palette.accentText)
            Spacer(minLength: 0)
            Text(entry.items == nil ? "Otwórz Terminka" : "Brak terminów")
                .font(DT.Typography.headline)
                .foregroundStyle(DT.Palette.textPrimary)
            Text(entry.items == nil ? "Widżet pokaże terminy po pierwszym uruchomieniu aplikacji." : "Dodaj pierwszy dokument.")
                .font(DT.Typography.caption)
                .foregroundStyle(DT.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(DT.Space.md)
        .containerBackground(for: .widget) { DT.Palette.backgroundElevated }
    }

    private func gradient(_ category: DocumentCategory, expired: Bool) -> some View {
        LinearGradient(colors: category.heroGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            .saturation(expired ? 0.5 : 1)
    }

    // MARK: Ekran blokady

    @ViewBuilder
    private var circular: some View {
        if let next {
            let d = days(next)
            Gauge(value: Double(max(0, min(30, d))), in: 0...30) {
                Image(systemName: category(next).symbol)
            } currentValueLabel: {
                Text(d == 0 ? "!" : "\(abs(d))").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(for: .widget) { Color.clear }
        } else {
            Image(systemName: "calendar.badge.clock")
                .containerBackground(for: .widget) { Color.clear }
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let next {
            VStack(alignment: .leading, spacing: 0) {
                Label("Terminek", systemImage: category(next).symbol)
                    .font(DT.Typography.captionEmphasized)
                    .widgetAccentable()
                Text(next.title)
                    .font(DT.Typography.headline)
                    .lineLimit(1)
                    .privacySensitive()
                Text(DaysText.sentence(days(next)).capitalizedFirst + ", " + PL.dayMonth(next.expiryDate))
                    .font(DT.Typography.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color.clear }
        } else {
            Text("Brak terminów")
                .containerBackground(for: .widget) { Color.clear }
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let next {
            Text("\(next.title) · \(DaysText.short(days(next)))")
                .privacySensitive()
                .containerBackground(for: .widget) { Color.clear }
        } else {
            Text("Terminek")
                .containerBackground(for: .widget) { Color.clear }
        }
    }
}

// MARK: - Centrum sterowania i przycisk czynności (iOS 18)

@available(iOS 18.0, *)
struct ScanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TerminekScan") {
            ControlWidgetButton(action: ScanDocumentIntent()) {
                Label("Skanuj dokument", systemImage: "doc.viewfinder")
            }
        }
        .displayName("Skanuj dokument")
        .description("Otwiera skaner Terminka.")
    }
}

@available(iOS 18.0, *)
struct AddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TerminekAdd") {
            ControlWidgetButton(action: AddDocumentIntent()) {
                Label("Dodaj dokument", systemImage: "plus.rectangle.on.rectangle")
            }
        }
        .displayName("Dodaj dokument")
        .description("Otwiera dodawanie dokumentu w Terminku.")
    }
}
