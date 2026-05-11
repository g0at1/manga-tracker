import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    let mangas: [Manga]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReadDay: ReadDayData?

    private var totalSeries: Int {
        mangas.count
    }

    private var totalVolumes: Int {
        mangas.flatMap { $0.volumes }.count
    }

    private var ownedVolumes: Int {
        mangas.flatMap { $0.volumes }.filter { $0.owned }.count
    }

    private var readVolumes: Int {
        mangas.flatMap { $0.volumes }.filter { $0.read == true }.count
    }

    private var totalSpent: Double {
        mangas
            .flatMap { $0.volumes }
            .filter { $0.owned }
            .compactMap { $0.price }
            .reduce(0, +)
    }

    private var readPercent: Double {
        guard totalVolumes > 0 else { return 0 }
        return (Double(readVolumes) / Double(totalVolumes)) * 100
    }

    private var mangaSpendData: [MangaSpendData] {
        mangas
            .map { manga in
                MangaSpendData(
                    title: manga.title,
                    amount: manga.volumes
                        .filter { $0.owned }
                        .compactMap { $0.price }
                        .reduce(0, +)
                )
            }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }

    private var mangaProgressData: [MangaProgressData] {
        mangas
            .map { manga in
                let total = manga.volumes.count
                let read = manga.volumes.filter { $0.read == true }.count
                let percent =
                    total > 0 ? (Double(read) / Double(total)) * 100 : 0

                return MangaProgressData(
                    title: manga.title,
                    totalVolumes: total,
                    readVolumes: read,
                    percent: percent
                )
            }
            .filter { $0.totalVolumes > 0 }
            .sorted { $0.percent > $1.percent }
    }

    private var monthlyPurchaseData: [MonthlyPurchaseData] {
        let calendar = Calendar.current

        let grouped = Dictionary(
            grouping: mangas.flatMap(\.volumes).filter {
                $0.owned && $0.purchaseDate != nil
            }
        ) {
            volume in
            let comps = calendar.dateComponents(
                [.year, .month],
                from: volume.purchaseDate!
            )
            return calendar.date(from: comps) ?? .now
        }

        return
            grouped
            .map { date, volumes in
                MonthlyPurchaseData(
                    month: date,
                    count: volumes.count,
                    amount: volumes.compactMap { $0.price }.reduce(0, +)
                )
            }
            .sorted { $0.month < $1.month }
    }

    private var readDayData: [ReadDayData] {
        let calendar = Calendar.current
        let entries =
            mangas
            .flatMap { $0.volumes }
            .compactMap { volume -> (Date, Volume)? in
                guard let readDate = volume.readDate else { return nil }
                return (calendar.startOfDay(for: readDate), volume)
            }

        let grouped = Dictionary(grouping: entries, by: { $0.0 })

        return
            grouped
            .map { day, values in
                let items =
                    values
                    .map { value in
                        let title = value.1.manga?.title ?? "Nieznany tytul"
                        return "\(title) #\(value.1.number)"
                    }
                    .sorted()

                return ReadDayData(
                    date: day,
                    count: values.count,
                    items: items
                )
            }
            .sorted { $0.date < $1.date }
    }

    private var readDayLookup: [Date: ReadDayData] {
        Dictionary(uniqueKeysWithValues: readDayData.map { ($0.date, $0) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summaryCards

                    if !readDayData.isEmpty {
                        DashboardCard("Aktywnosc czytania") {
                            VStack(alignment: .leading, spacing: 16) {
                                ReadHeatmapView(
                                    readDayLookup: readDayLookup,
                                    selectedDay: $selectedReadDay
                                )

                                if let selectedReadDay {
                                    VStack(
                                        alignment: .leading,
                                        spacing: 8
                                    ) {
                                        Text(
                                            selectedReadDay.date.yyyyMMdd()
                                        )
                                        .font(.headline)

                                        ForEach(
                                            selectedReadDay.items,
                                            id: \.self
                                        ) { item in
                                            Text(item)
                                                .font(.subheadline)
                                                .foregroundStyle(
                                                    .secondary
                                                )
                                        }
                                    }
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(
                                            cornerRadius: 12,
                                            style: .continuous
                                        )
                                        .fill(.white.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(
                                            cornerRadius: 12,
                                            style: .continuous
                                        )
                                        .stroke(
                                            .white.opacity(0.08),
                                            lineWidth: 1
                                        )
                                    )
                                } else {
                                    Text(
                                        "Wybierz dzien, aby zobaczyc co przeczytales."
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !mangaSpendData.isEmpty {
                        DashboardCard("Wydatki na serie") {
                            Chart(mangaSpendData.prefix(8)) { item in
                                BarMark(
                                    x: .value("Kwota", item.amount),
                                    y: .value("Manga", item.title)
                                )
                            }
                            .frame(height: 320)
                        }
                    }

                    if !mangaProgressData.isEmpty {
                        DashboardCard("Postęp czytania") {
                            Chart(mangaProgressData.prefix(10)) { item in
                                BarMark(
                                    x: .value("Postęp", item.percent),
                                    y: .value("Manga", item.title)
                                )
                            }
                            .frame(height: 320)
                        }
                    }

                    if !monthlyPurchaseData.isEmpty {
                        DashboardCard("Zakupy miesięczne") {
                            Chart(monthlyPurchaseData) { item in
                                LineMark(
                                    x: .value(
                                        "Miesiąc",
                                        item.month,
                                        unit: .month
                                    ),
                                    y: .value("Kupione tomy", item.count)
                                )

                                AreaMark(
                                    x: .value(
                                        "Miesiąc",
                                        item.month,
                                        unit: .month
                                    ),
                                    y: .value("Kupione tomy", item.count)
                                )
                                .opacity(0.2)
                            }
                            .frame(height: 260)
                        }

                        DashboardCard("Wydatki miesięczne") {
                            Chart(monthlyPurchaseData) { item in
                                BarMark(
                                    x: .value(
                                        "Miesiąc",
                                        item.month,
                                        unit: .month
                                    ),
                                    y: .value("Kwota", item.amount)
                                )
                            }
                            .frame(height: 260)
                        }
                    }

                    DashboardCard("Top serie") {
                        VStack(spacing: 12) {
                            ForEach(
                                Array(mangaSpendData.prefix(5).enumerated()),
                                id: \.offset
                            ) { index, item in
                                HStack {
                                    Text("\(index + 1).")
                                        .font(.headline)
                                        .frame(width: 28, alignment: .leading)

                                    Text(item.title)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(
                                        item.amount,
                                        format: .currency(code: "PLN")
                                    )
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                }

                                if index < min(mangaSpendData.count, 5) - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if selectedReadDay == nil {
                    selectedReadDay = readDayData.last
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 720)
    }

    private var summaryCards: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 180), spacing: 16)
            ],
            spacing: 16
        ) {
            SummaryCard(
                title: "Serie",
                value: "\(totalSeries)",
                systemImage: "books.vertical"
            )
            SummaryCard(
                title: "Wszystkie tomy",
                value: "\(totalVolumes)",
                systemImage: "square.stack.3d.up"
            )
            SummaryCard(
                title: "Kupione",
                value: "\(ownedVolumes)",
                systemImage: "cart"
            )
            SummaryCard(
                title: "Przeczytane",
                value: "\(readVolumes)",
                systemImage: "book.closed"
            )
            SummaryCard(
                title: "Wydano",
                value: totalSpent.formatted(.currency(code: "PLN")),
                systemImage: "creditcard"
            )
            SummaryCard(
                title: "Postęp",
                value: "\(Int(readPercent))%",
                systemImage: "chart.pie"
            )
        }
    }
}

// MARK: - Models

private struct MangaSpendData: Identifiable {
    let id = UUID()
    let title: String
    let amount: Double
}

private struct MangaProgressData: Identifiable {
    let id = UUID()
    let title: String
    let totalVolumes: Int
    let readVolumes: Int
    let percent: Double
}

private struct MonthlyPurchaseData: Identifiable {
    let id = UUID()
    let month: Date
    let count: Int
    let amount: Double
}

private struct ReadDayData: Identifiable {
    let date: Date
    let count: Int
    let items: [String]

    var id: Date { date }
}

// MARK: - Reusable UI

private struct DashboardCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.bold))

            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.green)

            Text(value)
                .font(.title.weight(.bold))

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

private struct ReadHeatmapView: View {
    let readDayLookup: [Date: ReadDayData]
    @Binding var selectedDay: ReadDayData?

    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 6

    private var calendar: Calendar {
        Calendar.current
    }

    private var weekdaySymbols: [String] {
        calendar.shortWeekdaySymbols
    }

    private var dateRange: (start: Date, end: Date) {
        let today = calendar.startOfDay(for: Date())
        let start =
            calendar.date(byAdding: .weekOfYear, value: -41, to: today)
            ?? today

        _ =
            calendar.dateInterval(of: .weekOfYear, for: start)?.start
            ?? start
        let endWeek =
            calendar.dateInterval(of: .weekOfYear, for: today)?.end
            ?? today
        let end = calendar.date(byAdding: .day, value: -1, to: endWeek) ?? today
        return (start: start, end: end)
    }

    private var weeks: [[Date]] {
        let start = dateRange.start
        let end = dateRange.end
        let startWeek =
            calendar.dateInterval(of: .weekOfYear, for: start)?.start
            ?? start

        var days: [Date] = []
        var current = startWeek
        while current <= end {
            days.append(current)
            current =
                calendar.date(byAdding: .day, value: 1, to: current)
                ?? current
        }

        return stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: cellSpacing) {
                VStack(alignment: .leading, spacing: cellSpacing) {
                    ForEach([1, 3, 5], id: \.self) { index in
                        Text(weekdaySymbols[index - 1])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(height: cellSize)
                    }
                }
                .frame(width: 22, alignment: .leading)

                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(weeks, id: \.first) { week in
                        VStack(spacing: cellSpacing) {
                            ForEach(week, id: \.self) { day in
                                dayCell(day)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Mniej")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    ForEach([0, 1, 2, 3, 4], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(for: level))
                            .frame(width: cellSize, height: cellSize)
                    }
                }

                Text("Wiecej")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let start = dateRange.start
        let end = calendar.startOfDay(for: Date())
        let isOutsideRange = day < start || day > end
        let readDay = readDayLookup[calendar.startOfDay(for: day)]
        let count = readDay?.count ?? 0

        Button {
            if !isOutsideRange, let readDay {
                selectedDay = readDay
            }
        } label: {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isOutsideRange ? .clear : color(for: count))
                .frame(width: cellSize, height: cellSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(
                            isSelected(day) ? .white.opacity(0.7) : .clear,
                            lineWidth: 1
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOutsideRange || readDay == nil)
    }

    private func isSelected(_ day: Date) -> Bool {
        guard let selectedDay else { return false }
        return calendar.isDate(selectedDay.date, inSameDayAs: day)
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0:
            return .white.opacity(0.06)
        case 1:
            return .green.opacity(0.28)
        case 2:
            return .green.opacity(0.45)
        case 3:
            return .green.opacity(0.62)
        default:
            return .green.opacity(0.82)
        }
    }
}
