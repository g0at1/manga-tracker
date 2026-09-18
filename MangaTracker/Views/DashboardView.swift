import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    let mangas: [Manga]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var selectedReadDay: ReadDayData?
    @State private var hoveredPurchase: MonthlyPurchaseData?

    private var totalSeries: Int {
        mangas.filter {
            !($0.isSold ?? false) && !($0.isSpinOff ?? false)
        }.count
    }

    private var totalVolumes: Int {
        mangas.filter { !($0.isSold ?? false) }.flatMap { $0.volumes }.count
    }

    private var ownedVolumes: Int {
        mangas.filter { !($0.isSold ?? false) }.flatMap { $0.volumes }.filter { $0.owned }.count
    }

    private var readVolumes: Int {
        mangas.filter { !($0.isSold ?? false) }.flatMap { $0.volumes }.filter { $0.read == true }.count
    }

    private var averageVolumePrice: Double {
        let prices = mangas
            .filter { !($0.isSold ?? false) }
            .flatMap { $0.volumes }
            .filter { $0.owned }
            .compactMap { $0.price }

        guard !prices.isEmpty else { return 0 }

        return prices.reduce(0, +) / Double(prices.count)
    }

    private var currentMonthSpending: Double {
        let calendar = Calendar.current
        let now = Date()

        return monthlyPurchaseData.first {
            calendar.isDate(
                $0.month,
                equalTo: now,
                toGranularity: .month
            )
        }?.amount ?? 0
    }

    private var previousMonthSpending: Double {
        let calendar = Calendar.current

        guard let previousMonth = calendar.date(
            byAdding: .month,
            value: -1,
            to: Date()
        ) else {
            return 0
        }

        return monthlyPurchaseData.first {
            calendar.isDate(
                $0.month,
                equalTo: previousMonth,
                toGranularity: .month
            )
        }?.amount ?? 0
    }

    private var monthlySpendingDifference: Double {
        currentMonthSpending - previousMonthSpending
    }

    private var monthlySpendingPercentChange: Double? {
        guard previousMonthSpending > 0 else {
            return nil
        }

        return (monthlySpendingDifference / previousMonthSpending) * 100
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
            .filter { $0.totalVolumes > 0 && $0.percent < 100 }
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
                                let title = value.1.manga?.title ?? L("Nieznany tytuł")
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
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                header

                summaryTiles

                HStack(alignment: .top, spacing: 18) {
                    readingActivityCard
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 18) {
                        monthComparisonCard
                        topSeriesCard
                    }
                    .frame(width: 340)
                }

                HStack(alignment: .top, spacing: 18) {
                    spendingPerSeriesCard
                    progressPerSeriesCard
                }

                HStack(alignment: .top, spacing: 18) {
                    monthlyPurchasesCard
                    monthlySpendingCard
                }
            }
            .padding(28)
        }
        .frame(minWidth: 1100, minHeight: 760)
        .background(AppBackgroundView())
        .navigationTitle("Statystyki")
        .onAppear {
            if selectedReadDay == nil {
                selectedReadDay = readDayData.last
            }
            WindowManager.ensureComfortableSize(windowID: "dashboard", minWidth: 1400, minHeight: 900)
        }
    }

    // MARK: - Header & tiles

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Statystyki")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Twoja kolekcja w liczbach")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 175, maximum: 260), spacing: 12)], spacing: 12) {
            StatCardView(title: "serii", value: "\(totalSeries)", systemImage: "books.vertical.fill", accentColor: .blue, expands: true)
            StatCardView(title: "wszystkich tomów", value: "\(totalVolumes)", systemImage: "square.stack.3d.up.fill", accentColor: .teal, expands: true)
            StatCardView(title: "kupionych", value: "\(ownedVolumes)", systemImage: "cart.fill", accentColor: .green, expands: true)
            StatCardView(title: "przeczytanych", value: "\(readVolumes)", systemImage: "checkmark.circle.fill", accentColor: .green, expands: true)
            StatCardView(
                title: "średnia cena tomu",
                value: averageVolumePrice.formatted(.number.precision(.fractionLength(2)).locale(locale)),
                systemImage: "tag.fill",
                accentColor: .orange,
                unit: "PLN",
                expands: true
            )
            StatCardView(
                title: "postęp",
                value: readPercent.formatted(.number.precision(.fractionLength(1)).locale(locale)) + "%",
                systemImage: "circle.dashed.inset.filled",
                accentColor: .green,
                expands: true
            )
        }
    }

    // MARK: - Reading activity

    private var readingActivityCard: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 16) {
                DetailCardTitle(title: "Aktywność czytania", systemImage: "flame.fill")

                if readDayData.isEmpty {
                    emptyNote("Oznacz tom jako przeczytany, a tutaj pojawi się Twoja aktywność.")
                } else {
                    ReadHeatmapView(readDayLookup: readDayLookup, selectedDay: $selectedReadDay)

                    if let selectedReadDay {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(selectedReadDay.date.yyyyMMdd())
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(selectedReadDay.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.green)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.16), in: Capsule())
                            }
                            ForEach(selectedReadDay.items, id: \.self) { item in
                                Label(item, systemImage: "book.closed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    } else {
                        emptyNote("Wybierz dzień, aby zobaczyć co przeczytałeś.")
                    }
                }
            }
        }
    }

    // MARK: - Month comparison & top series

    private var monthComparisonCard: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Ten miesiąc vs poprzedni", systemImage: "calendar")

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ten miesiąc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(currentMonthSpending, format: .currency(code: "PLN"))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Poprzedni miesiąc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(previousMonthSpending, format: .currency(code: "PLN"))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: monthlySpendingDifference > 0
                        ? "arrow.up.right" : monthlySpendingDifference < 0 ? "arrow.down.right" : "minus")
                        .font(.caption.weight(.bold))
                    if let percent = monthlySpendingPercentChange {
                        (Text(percent, format: .number.precision(.fractionLength(1))) + Text("%"))
                            .monospacedDigit()
                    } else {
                        Text("—")
                    }
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(monthlySpendingDifference, format: .currency(code: "PLN"))
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    monthlySpendingDifference > 0 ? Color.red
                        : monthlySpendingDifference < 0 ? Color.green : Color.secondary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        (monthlySpendingDifference > 0 ? Color.red
                            : monthlySpendingDifference < 0 ? Color.green : Color.white)
                            .opacity(0.12)
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var topSeriesCard: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 12) {
                DetailCardTitle(title: "Top serie", systemImage: "crown.fill")

                if mangaSpendData.isEmpty {
                    emptyNote("Wpisz ceny tomów, aby zobaczyć ranking.")
                } else {
                    let top = Array(mangaSpendData.prefix(5))
                    let maxAmount = top.first?.amount ?? 1
                    VStack(spacing: 10) {
                        ForEach(Array(top.enumerated()), id: \.offset) { index, item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(index == 0 ? Color.black.opacity(0.85) : .secondary)
                                        .frame(width: 20, height: 20)
                                        .background(
                                            Circle().fill(index == 0 ? Color.green : Color.white.opacity(0.08))
                                        )
                                    Text(item.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(item.amount, format: .currency(code: "PLN"))
                                        .font(.caption.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(Color.green.opacity(index == 0 ? 0.9 : 0.45))
                                        .frame(width: max(4, geo.size.width * item.amount / maxAmount))
                                }
                                .frame(height: 4)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Charts

    private var spendingPerSeriesCard: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Wydatki na serie", systemImage: "banknote.fill")

                if mangaSpendData.isEmpty {
                    emptyNote("Wpisz ceny tomów, aby zobaczyć wykres.")
                } else {
                    Chart(mangaSpendData.prefix(8)) { item in
                        BarMark(
                            x: .value("Kwota", item.amount),
                            y: .value("Manga", item.title)
                        )
                        .foregroundStyle(Color.green.gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing, spacing: 6) {
                            Text(item.amount, format: .number.precision(.fractionLength(0)))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 280)
                }
            }
        }
    }

    private var progressPerSeriesCard: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Postęp czytania", systemImage: "chart.bar.fill")

                if mangaProgressData.isEmpty {
                    emptyNote("Wszystko przeczytane — nie ma czego pokazać.")
                } else {
                    Chart(mangaProgressData.prefix(8)) { item in
                        BarMark(
                            x: .value("Postęp", item.percent),
                            y: .value("Manga", item.title)
                        )
                        .foregroundStyle(Color.teal.gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing, spacing: 6) {
                            Text("\(item.readVolumes)/\(item.totalVolumes)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXScale(domain: 0 ... 100)
                    .chartXAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                            AxisValueLabel {
                                if let v = value.as(Int.self) {
                                    Text("\(v)%").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 280)
                }
            }
        }
    }

    private var monthlyPurchasesCard: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Zakupy miesięczne", systemImage: "cart.fill")

                if monthlyPurchaseData.isEmpty {
                    emptyNote("Ustaw daty zakupu tomów, aby zobaczyć wykres.")
                } else {
                    Chart(monthlyPurchaseData) { item in
                        AreaMark(
                            x: .value("Miesiąc", item.month, unit: .month),
                            y: .value("Kupione tomy", item.count)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green.opacity(0.35), Color.green.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Miesiąc", item.month, unit: .month),
                            y: .value("Kupione tomy", item.count)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Miesiąc", item.month, unit: .month),
                            y: .value("Kupione tomy", item.count)
                        )
                        .foregroundStyle(Color.green)
                        .symbolSize(30)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) { _ in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                            AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                            AxisValueLabel()
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 240)
                }
            }
        }
    }

    private var monthlySpendingCard: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Wydatki miesięczne", systemImage: "creditcard.fill")

                if monthlyPurchaseData.isEmpty {
                    emptyNote("Ustaw daty zakupu tomów, aby zobaczyć wykres.")
                } else {
                    Chart {
                        ForEach(monthlyPurchaseData) { item in
                            BarMark(
                                x: .value("Miesiąc", item.month, unit: .month),
                                y: .value("Kwota", item.amount)
                            )
                            .foregroundStyle(Color.yellow.gradient)
                            .cornerRadius(4)
                            .opacity(hoveredPurchase == nil || hoveredPurchase?.id == item.id ? 1 : 0.4)
                        }

                        if let hoveredPurchase {
                            RuleMark(x: .value("Miesiąc", hoveredPurchase.month))
                                .foregroundStyle(Color.white.opacity(0.25))
                                .annotation(position: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hoveredPurchase.month.formatted(.dateTime.month(.wide).year().locale(locale)))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(hoveredPurchase.amount, format: .currency(code: "PLN"))
                                            .font(.caption.weight(.bold))
                                            .monospacedDigit()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color(red: 0.1, green: 0.11, blue: 0.12))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                                }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) { _ in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                            AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                            AxisValueLabel()
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case let .active(location):
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let frame = geometry[plotFrame]
                                        let x = location.x - frame.origin.x
                                        guard x >= 0, x <= frame.width, let date: Date = proxy.value(atX: x) else {
                                            hoveredPurchase = nil
                                            return
                                        }
                                        hoveredPurchase = monthlyPurchaseData.min {
                                            abs($0.month.timeIntervalSince(date)) < abs($1.month.timeIntervalSince(date))
                                        }
                                    case .ended:
                                        hoveredPurchase = nil
                                    }
                                }
                        }
                    }
                    .frame(height: 240)
                }
            }
        }
    }

    private func emptyNote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
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

    var id: Date {
        date
    }
}

// MARK: - Heatmap

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
            Array(days[$0 ..< min($0 + 7, days.count)])
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

                Text("Więcej")
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
