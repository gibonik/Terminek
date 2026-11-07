import SwiftUI
import SwiftData

struct CalendarScreen: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Document.expiryDate) private var documents: [Document]
    @State private var month: Date = PL.calendar.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay: Date?

    private let cal = PL.calendar

    private var monthDocuments: [Document] {
        documents.filter { cal.isDate($0.expiryDate, equalTo: month, toGranularity: .month) }
    }

    private var listed: [Document] {
        guard let selectedDay else { return monthDocuments }
        return monthDocuments.filter { cal.isDate($0.expiryDate, inSameDayAs: selectedDay) }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.calendarPath) {
            List {
                Section {
                    MonthGrid(month: month, documents: monthDocuments, selectedDay: $selectedDay)
                        .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
                }

                Section {
                    if listed.isEmpty {
                        Text(selectedDay == nil ? "Brak terminów w tym miesiącu." : "Tego dnia nic się nie kończy.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(listed) { doc in
                            NavigationLink(value: doc) {
                                DocumentRow(document: doc)
                            }
                        }
                    }
                } header: {
                    Text(listTitle)
                }
                .headerProminence(.increased)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .navigationTitle(monthTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Dziś") { show(.now) }
                        .disabled(cal.isDate(month, equalTo: .now, toGranularity: .month) && selectedDay == nil)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { step(-1) } label: { Label("Poprzedni miesiąc", systemImage: "chevron.left") }
                    Button { step(1) } label: { Label("Następny miesiąc", systemImage: "chevron.right") }
                }
            }
            .navigationDestination(for: Document.self) { DocumentDetailView(document: $0) }
        }
        .sensoryFeedback(.selection, trigger: month)
    }

    private var monthTitle: String {
        let year = cal.component(.year, from: month)
        let name = PL.monthName(month)
        return year == cal.component(.year, from: .now) ? name : "\(name) \(year)"
    }

    private var listTitle: String {
        if let selectedDay {
            let text = PL.dayAndMonth(selectedDay)
            return String(text.prefix(1)).uppercased() + String(text.dropFirst())
        }
        return "Cały miesiąc"
    }

    private func step(_ delta: Int) {
        guard let next = cal.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(.snappy) {
            month = next
            selectedDay = nil
        }
    }

    private func show(_ date: Date) {
        withAnimation(.snappy) {
            month = cal.dateInterval(of: .month, for: date)?.start ?? date
            selectedDay = cal.startOfDay(for: date)
        }
    }
}

/// Siatka miesiąca od poniedziałku. Kropki pod dniem mają kolory grup dokumentów.
struct MonthGrid: View {
    let month: Date
    let documents: [Document]
    @Binding var selectedDay: Date?

    private let cal = PL.calendar
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var days: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let leading = (cal.component(.weekday, from: interval.start) + 5) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<count {
            result.append(cal.date(byAdding: .day, value: offset, to: interval.start))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(PL.weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day)
                    } else {
                        Color.clear.frame(height: 50)
                    }
                }
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        let docs = documents.filter { cal.isDate($0.expiryDate, inSameDayAs: day) }
        let isToday = cal.isDateInToday(day)
        let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let hasExpired = docs.contains { $0.daysLeft() < 0 }
        let groups = Array(Set(docs.map(\.group))).sorted { $0.rawValue < $1.rawValue }

        return Button {
            withAnimation(.snappy) { selectedDay = isSelected ? nil : day }
        } label: {
            VStack(spacing: 4) {
                Text(cal.component(.day, from: day).formatted())
                    .font(.body.weight(isToday || isSelected ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Palette.tint : (hasExpired ? Palette.expired : Color.primary)))
                    .frame(width: 36, height: 36)
                    .background {
                        if isSelected {
                            Circle().fill(Palette.tint)
                        } else if isToday {
                            Circle().stroke(Palette.tint, lineWidth: 1.5)
                        }
                    }
                HStack(spacing: 3) {
                    ForEach(groups.prefix(3)) { group in
                        Circle().fill(group.color).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(PL.date(day))
        .accessibilityValue(docs.isEmpty ? "" : docs.map(\.displayTitle).joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
