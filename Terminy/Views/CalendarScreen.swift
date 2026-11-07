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
            VStack(alignment: .leading, spacing: DT.Space.gutter) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: DT.Space.xxs) {
                        Text(verbatim: String(cal.component(.year, from: month)))
                            .font(DT.Typography.subheadline)
                            .foregroundStyle(DT.Palette.textSecondary)
                            .contentTransition(.numericText())
                        Text(PL.monthName(month))
                            .font(DT.Typography.largeTitle)
                            .contentTransition(.interpolate)
                    }
                    Spacer()
                    HStack(spacing: DT.Space.xs) {
                        RoundIconButton(symbol: "chevron.left", label: "Poprzedni miesiąc") { step(-1) }
                        RoundIconButton(symbol: "chevron.right", label: "Następny miesiąc") { step(1) }
                    }
                }
                .padding(.horizontal, DT.Space.xxs)

                MonthGrid(month: month, documents: monthDocuments, selectedDay: $selectedDay)
                    .id(month)
                    .transition(.push(from: forward ? .trailing : .leading))
                    .padding(DT.Space.sm)
                    .panel()
                    .gesture(
                        DragGesture(minimumDistance: DT.Space.lg).onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                            step(value.translation.width < 0 ? 1 : -1)
                        }
                    )

                HStack {
                    SectionHeader(text: listTitle)
                    if selectedDay != nil || !cal.isDate(month, equalTo: .now, toGranularity: .month) {
                        Button("Dziś") { show(.now) }
                            .font(DT.Typography.subheadlineEmphasized)
                            .foregroundStyle(DT.Palette.accentText)
                            .frame(minHeight: DT.Size.touch)
                    }
                }

                if listed.isEmpty {
                    Text(selectedDay == nil ? "W tym miesiącu nic się nie kończy." : "Tego dnia nic się nie kończy.")
                        .font(DT.Typography.body)
                        .foregroundStyle(DT.Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: DT.Size.tile)
                        .panel()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(listed.enumerated()), id: \.element.id) { index, doc in
                            if index > 0 { Rectangle().fill(DT.Palette.separator).frame(height: DT.Size.hairline).padding(.leading, DT.Space.md * 2 + DT.Size.miniCard.width) }
                            Button { router.open(doc, from: "cal-\(doc.id)") } label: {
                                DocRow(document: doc)
                            }
                            .buttonStyle(CardPressStyle())
                            .zoomSource("cal-\(doc.id)")
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .panel()
                }
            }
            .padding(.horizontal, DT.Space.gutter)
            .padding(.top, DT.Space.xs)
            .padding(.bottom, DT.Space.tabBarClearance)
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
        VStack(spacing: DT.Space.xs) {
            HStack(spacing: 0) {
                ForEach(PL.weekdays, id: \.self) { day in
                    Text(day)
                        .font(DT.Typography.caption)
                        .foregroundStyle(DT.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: DT.Space.xxs) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day)
                    } else {
                        Color.clear.frame(height: DT.Size.dayCell + DT.Space.sm)
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
            VStack(spacing: DT.Space.xxs) {
                Text(cal.component(.day, from: day).formatted())
                    .font(isToday || isSelected ? DT.Typography.headline : DT.Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? DT.Palette.onAccent : (isToday ? DT.Palette.accent : (hasExpired ? DT.Palette.danger : DT.Palette.textPrimary)))
                    .frame(width: DT.Size.dayCell, height: DT.Size.dayCell)
                    .background {
                        if isSelected {
                            Circle().fill(DT.Palette.accent)
                                .matchedGeometryEffect(id: "selected", in: selection)
                        } else if isToday {
                            Circle().strokeBorder(DT.Palette.accent, lineWidth: DT.Size.hairline * 2)
                        }
                    }
                HStack(spacing: DT.Space.xxs) {
                    ForEach(groups.prefix(3)) { group in
                        Circle().fill(group.color).frame(width: DT.Size.dot, height: DT.Size.dot)
                    }
                }
                .frame(height: DT.Size.dot)
            }
            .frame(maxWidth: .infinity, minHeight: DT.Size.dayCell + DT.Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PL.date(day))
        .accessibilityValue(docs.isEmpty ? "" : docs.map(\.displayTitle).joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
