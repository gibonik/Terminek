import SwiftUI
import SwiftData

/// Zakładka „Kalendarz”: miesiąc z kolorowymi kropkami terminów i lista pod spodem.
struct CalendarView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Document.expiryDate) private var documents: [Document]

    @State private var month = PL.calendar.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay: Date?
    @State private var direction: Edge = .trailing

    private let cal = PL.calendar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header.riseIn(0)
                grid.riseIn(1)
                list.riseIn(2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .tabBarClearance()
        .background(Palette.bg.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: selectedDay)
        .sensoryFeedback(.selection, trigger: month)
    }

    // MARK: Nagłówek z przełączaniem miesięcy

    private var header: some View {
        let comps = cal.dateComponents([.year, .month], from: month)
        let isThisYear = comps.year == cal.component(.year, from: .now)
        return ScreenHeader(title: PL.months[(comps.month ?? 1) - 1],
                            subtitle: isThisYear ? "Kalendarz" : "Kalendarz · \(comps.year ?? 0)") {
            HStack(spacing: 8) {
                CircleIconButton(symbol: "chevron.left", label: "Poprzedni miesiąc") { shift(-1) }
                CircleIconButton(symbol: "chevron.right", label: "Następny miesiąc") { shift(1) }
            }
        }
    }

    private func shift(_ value: Int) {
        direction = value > 0 ? .trailing : .leading
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
            month = cal.date(byAdding: .month, value: value, to: month) ?? month
            selectedDay = nil
        }
    }

    // MARK: Siatka dni

    private var days: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = cal.component(.weekday, from: month)       // 1 = niedziela
        let leading = (weekday + 5) % 7                           // poniedziałek = 0
        var result: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            result.append(cal.date(byAdding: .day, value: day - 1, to: month))
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private func docs(on day: Date) -> [Document] {
        documents.filter { cal.isDate($0.expiryDate, inSameDayAs: day) }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(PL.weekdays, id: \.self) { name in
                Text(name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .padding(.bottom, 4)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 42)
                }
            }
        }
        .padding(14)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .id(month)
        .transition(.asymmetric(insertion: .move(edge: direction).combined(with: .opacity),
                                removal: .opacity))
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = cal.isDateInToday(day)
        let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let isPast = day < cal.startOfDay(for: .now)
        let items = docs(on: day)

        return Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                selectedDay = isSelected ? nil : day
            }
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 14, weight: items.isEmpty && !isToday ? .semibold : .heavy).monospacedDigit())
                HStack(spacing: 2) {
                    ForEach(items.prefix(3)) { doc in
                        Circle()
                            .fill(doc.daysLeft() < 0 ? Palette.alert : doc.group.color)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(height: 6)
            }
            .foregroundStyle(isToday ? Palette.bg : (isPast ? Palette.muted : Palette.ink))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isToday ? Palette.ink : (isSelected ? Palette.tile : .clear))
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.ink, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PL.date(day) + (items.isEmpty ? "" : ", terminów: \(items.count)"))
    }

    // MARK: Lista terminów

    private var monthDocs: [Document] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        return documents.filter { interval.contains($0.expiryDate) }
    }

    private var list: some View {
        let items = selectedDay.map(docs(on:)) ?? monthDocs
        return VStack(alignment: .leading, spacing: 8) {
            Text(listTitle(count: items.count).uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 6)
            if items.isEmpty {
                Text(selectedDay == nil ? "W tym miesiącu nic nie wygasa." : "Tego dnia nic nie wygasa.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            ForEach(items) { doc in
                Button { router.selected = doc } label: { CalendarRow(document: doc) }
                    .buttonStyle(PressScaleStyle(scale: 0.98))
            }
        }
    }

    private func listTitle(count: Int) -> String {
        if let selectedDay { return PL.date(selectedDay) }
        return count == 0 ? "Terminy w miesiącu" : "Terminy w miesiącu · \(count)"
    }
}

private struct CalendarRow: View {
    let document: Document

    var body: some View {
        let group = document.group
        let cal = PL.calendar
        let comps = cal.dateComponents([.day, .month], from: document.expiryDate)
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text("\(comps.day ?? 1)").font(.system(size: 16, weight: .heavy))
                Text(PL.monthsShort[(comps.month ?? 1) - 1]).font(.system(size: 9, weight: .heavy))
            }
            .foregroundStyle(group.ink)
            .frame(width: 42, height: 42)
            .background(group.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(document.displayTitle)
                    .font(.system(size: 15, weight: .heavy))
                    .lineLimit(1)
                Text(document.cardSubtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            DaysChip(days: document.daysLeft(), size: 12)
        }
        .padding(12)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
