import SwiftUI
import SwiftData

struct CalendarScreen: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Document.expiryDate) private var documents: [Document]
    @State private var month: Date = PL.calendar.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay: Date?
    @State private var forward = true

    private let cal = PL.calendar

    private var monthDocuments: [Document] {
        documents.filter { cal.isDate($0.expiryDate, equalTo: month, toGranularity: .month) }
    }

    private var listed: [Document] {
        guard let selectedDay else { return monthDocuments }
        return monthDocuments.filter { cal.isDate($0.expiryDate, inSameDayAs: selectedDay) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: String(cal.component(.year, from: month)))
                            .font(.brico(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(W.muted)
                            .contentTransition(.numericText())
                        Text(PL.monthName(month))
                            .font(.brico(44, .heavy, relativeTo: .largeTitle))
                            .tracking(-1.5)
                            .contentTransition(.interpolate)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        RoundIconButton(symbol: "chevron.left", label: "Poprzedni miesiąc") { step(-1) }
                        RoundIconButton(symbol: "chevron.right", label: "Następny miesiąc") { step(1) }
                    }
                }
                .padding(.horizontal, 4)

                MonthGrid(month: month, documents: monthDocuments, selectedDay: $selectedDay)
                    .id(month)
                    .transition(.push(from: forward ? .trailing : .leading))
                    .padding(12)
                    .walletPanel(radius: 26)
                    .gesture(
                        DragGesture(minimumDistance: 24).onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                            step(value.translation.width < 0 ? 1 : -1)
                        }
                    )

                HStack {
                    WalletSectionTitle(text: listTitle)
                    if selectedDay != nil || !cal.isDate(month, equalTo: .now, toGranularity: .month) {
                        Button("Dziś") { show(.now) }
                            .font(.brico(15, .bold))
                            .foregroundStyle(W.gold)
                            .frame(minHeight: 44)
                    }
                }

                if listed.isEmpty {
                    Text(selectedDay == nil ? "W tym miesiącu nic się nie kończy." : "Tego dnia nic się nie kończy.")
                        .font(.brico(16, .medium))
                        .foregroundStyle(W.muted)
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .walletPanel()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(listed.enumerated()), id: \.element.id) { index, doc in
                            if index > 0 { Rectangle().fill(W.stroke).frame(height: 1).padding(.leading, 76) }
                            Button { router.tab = .home; router.open(doc) } label: {
                                DocRow(document: doc)
                            }
                            .buttonStyle(CardPressStyle())
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .walletPanel()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: month)
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
        forward = delta > 0
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
            month = next
            selectedDay = nil
        }
    }

    private func show(_ date: Date) {
        let target = cal.dateInterval(of: .month, for: date)?.start ?? date
        forward = target > month
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
            month = target
            selectedDay = cal.startOfDay(for: date)
        }
    }
}

/// Siatka miesiąca od poniedziałku. Kropki pod dniem mają kolory grup dokumentów.
struct MonthGrid: View {
    let month: Date
    let documents: [Document]
    @Binding var selectedDay: Date?

    @Namespace private var selection
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
                        .font(.brico(12, .medium, relativeTo: .caption))
                        .foregroundStyle(W.faint)
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
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { selectedDay = isSelected ? nil : day }
        } label: {
            VStack(spacing: 4) {
                Text(cal.component(.day, from: day).formatted())
                    .font(.brico(17, isToday || isSelected ? .heavy : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? W.goldInk : (isToday ? W.gold : (hasExpired ? Palette.expired : W.cream)))
                    .frame(width: 38, height: 38)
                    .background {
                        if isSelected {
                            Circle().fill(W.gold)
                                .matchedGeometryEffect(id: "selected", in: selection)
                        } else if isToday {
                            Circle().strokeBorder(W.gold, lineWidth: 1.5)
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
        .buttonStyle(.plain)
        .accessibilityLabel(PL.date(day))
        .accessibilityValue(docs.isEmpty ? "" : docs.map(\.displayTitle).joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
