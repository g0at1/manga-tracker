import SwiftUI

/// Month calendar for picking a single day, styled like the rest of the app
/// (the system graphical picker is small and follows the system accent).
struct CalendarPickerView: View {
    @Binding var selection: Date

    @Environment(\.locale) private var locale
    @State private var displayedMonth: Date

    private let cellSize: CGFloat = 36
    private let spacing: CGFloat = 4

    init(selection: Binding<Date>) {
        _selection = selection
        _displayedMonth = State(initialValue: selection.wrappedValue)
    }

    private var calendar: Calendar {
        var calendar = locale.calendar
        calendar.locale = locale
        return calendar
    }

    /// Days shown in the grid: leading/trailing days of neighbouring months
    /// fill the first and last week so the grid is always full rows.
    private var days: [Date] {
        let calendar = calendar
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else { return [] }

        var result: [Date] = []
        var current = firstWeek.start
        while current < lastWeek.end {
            result.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? lastWeek.end
        }
        return result
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: 10) {
            header

            HStack(spacing: spacing) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: cellSize)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: 7), spacing: spacing) {
                ForEach(days, id: \.self) { day in
                    DayCell(
                        day: calendar.component(.day, from: day),
                        isInMonth: calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month),
                        isSelected: calendar.isDate(day, inSameDayAs: selection),
                        isToday: calendar.isDateInToday(day),
                        size: cellSize
                    ) {
                        selection = day
                        displayedMonth = day
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(displayedMonth.formatted(.dateTime.month(.wide).year().locale(locale)).capitalized)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            SubtleButton(title: "Dziś", tint: .green) {
                let today = Date()
                selection = today
                displayedMonth = today
            }

            NavButton(systemImage: "chevron.left") { shiftMonth(-1) }
            NavButton(systemImage: "chevron.right") { shiftMonth(1) }
        }
        .padding(.horizontal, 2)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }
}

private struct NavButton: View {
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(isHovered ? 0.12 : 0.06)))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct DayCell: View {
    let day: Int
    let isInMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let size: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("\(day)")
                .font(.system(size: 13, weight: isSelected || isToday ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(
                        isSelected ? Color.green : Color.white.opacity(isHovered ? 0.1 : 0)
                    )
                )
                .overlay(
                    Circle().stroke(isToday && !isSelected ? Color.green.opacity(0.7) : .clear, lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    private var foreground: Color {
        if isSelected { return Color.black.opacity(0.85) }
        if !isInMonth { return Color.secondary.opacity(0.4) }
        if isToday { return .green }
        return .primary
    }
}
