import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    let mangas: [Manga]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        // One pass over the library; hover and selection state live in the
        // cards below so mouse movement never triggers this again.
        let data = DashboardData(mangas: mangas)

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                header

                summaryTiles(data)

                HStack(alignment: .top, spacing: 18) {
                    ReadingActivityCard(readDays: data.readDays, readDayLookup: data.readDayLookup)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 18) {
                        monthComparisonCard(data)
                        topSeriesCard(data.mangaSpend)
                    }
                    .frame(width: 340)
                }

                HStack(alignment: .top, spacing: 18) {
                    spendingPerSeriesCard(data.mangaSpend)
                    progressPerSeriesCard(data.mangaProgress)
                }

                HStack(alignment: .top, spacing: 18) {
                    monthlyPurchasesCard(data.monthlyPurchases)
                    MonthlySpendingCard(monthlyPurchases: data.monthlyPurchases)
                }
            }
            .padding(28)
        }
        .frame(minWidth: 1100, minHeight: 760)
        .background(AppBackgroundView())
        .navigationTitle("Statystyki")
        .onAppear {
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

    private func summaryTiles(_ data: DashboardData) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 175, maximum: 260), spacing: 12)], spacing: 12) {
            StatCardView(title: "serii", value: "\(data.totalSeries)", systemImage: "books.vertical.fill", accentColor: .blue, expands: true)
            StatCardView(title: "wszystkich tomów", value: "\(data.totalVolumes)", systemImage: "square.stack.3d.up.fill", accentColor: .teal, expands: true)
            StatCardView(title: "kupionych", value: "\(data.ownedVolumes)", systemImage: "cart.fill", accentColor: .green, expands: true)
            StatCardView(title: "przeczytanych", value: "\(data.readVolumes)", systemImage: "checkmark.circle.fill", accentColor: .green, expands: true)
            StatCardView(
                title: "średnia cena tomu",
                value: data.averageVolumePrice.formatted(.number.precision(.fractionLength(2)).locale(locale)),
                systemImage: "tag.fill",
                accentColor: .orange,
                unit: "PLN",
                expands: true
            )
            StatCardView(
                title: "postęp",
                value: data.readPercent.formatted(.number.precision(.fractionLength(1)).locale(locale)) + "%",
                systemImage: "circle.dashed.inset.filled",
                accentColor: .green,
                expands: true
            )
        }
    }

    // MARK: - Month comparison & top series

    private func monthComparisonCard(_ data: DashboardData) -> some View {
        let difference = data.monthlySpendingDifference

        return DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Ten miesiąc vs poprzedni", systemImage: "calendar")

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ten miesiąc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(data.currentMonthSpending, format: .currency(code: "PLN"))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Poprzedni miesiąc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(data.previousMonthSpending, format: .currency(code: "PLN"))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: difference > 0
                        ? "arrow.up.right" : difference < 0 ? "arrow.down.right" : "minus")
                        .font(.caption.weight(.bold))
                    if let percent = data.monthlySpendingPercentChange {
                        (Text(percent, format: .number.precision(.fractionLength(1))) + Text("%"))
                            .monospacedDigit()
                    } else {
                        Text("—")
                    }
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(difference, format: .currency(code: "PLN"))
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    difference > 0 ? Color.red
                        : difference < 0 ? Color.green : Color.secondary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        (difference > 0 ? Color.red
                            : difference < 0 ? Color.green : Color.white)
                            .opacity(0.12)
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func topSeriesCard(_ mangaSpend: [MangaSpendData]) -> some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 12) {
                DetailCardTitle(title: "Top serie", systemImage: "crown.fill")

                if mangaSpend.isEmpty {
                    emptyNote("Wpisz ceny tomów, aby zobaczyć ranking.")
                } else {
                    let top = Array(mangaSpend.prefix(5))
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

    private func spendingPerSeriesCard(_ mangaSpend: [MangaSpendData]) -> some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Wydatki na serie", systemImage: "banknote.fill")

                if mangaSpend.isEmpty {
                    emptyNote("Wpisz ceny tomów, aby zobaczyć wykres.")
                } else {
                    Chart(mangaSpend.prefix(8)) { item in
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

    private func progressPerSeriesCard(_ mangaProgress: [MangaProgressData]) -> some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Postęp czytania", systemImage: "chart.bar.fill")

                if mangaProgress.isEmpty {
                    emptyNote("Wszystko przeczytane — nie ma czego pokazać.")
                } else {
                    Chart(mangaProgress.prefix(8)) { item in
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

    private func monthlyPurchasesCard(_ monthlyPurchases: [MonthlyPurchaseData]) -> some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Zakupy miesięczne", systemImage: "cart.fill")

                if monthlyPurchases.isEmpty {
                    emptyNote("Ustaw daty zakupu tomów, aby zobaczyć wykres.")
                } else {
                    Chart(monthlyPurchases) { item in
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
}

private func emptyNote(_ text: LocalizedStringKey) -> some View {
    Text(text)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
}

// MARK: - Models

// Identities are the series or the month, not a fresh UUID, so Charts and
// ForEach can diff between renders and a hovered/selected item stays matched.

private struct MangaSpendData: Identifiable {
    let id: PersistentIdentifier
    let title: String
    let amount: Double
}

private struct MangaProgressData: Identifiable {
    let id: PersistentIdentifier
    let title: String
    let totalVolumes: Int
    let readVolumes: Int
    let percent: Double
}

private struct MonthlyPurchaseData: Identifiable, Equatable {
    let month: Date
    let count: Int
    let amount: Double

    var id: Date {
        month
    }
}

private struct ReadDayData: Identifiable, Equatable {
    let date: Date
    let count: Int
    let items: [String]

    var id: Date {
        date
    }
}

/// Everything the dashboard shows, derived from the library in one pass.
private struct DashboardData {
    /// Series that aren't sold or spin-offs.
    let totalSeries: Int
    let totalVolumes: Int
    let ownedVolumes: Int
    let readVolumes: Int
    let averageVolumePrice: Double
    /// Most expensive series first; series without prices are left out.
    let mangaSpend: [MangaSpendData]
    /// Unfinished series, closest to done first.
    let mangaProgress: [MangaProgressData]
    let monthlyPurchases: [MonthlyPurchaseData]
    let readDays: [ReadDayData]
    let readDayLookup: [Date: ReadDayData]
    let currentMonthSpending: Double
    let previousMonthSpending: Double

    var readPercent: Double {
        totalVolumes > 0 ? Double(readVolumes) / Double(totalVolumes) * 100 : 0
    }

    var monthlySpendingDifference: Double {
        currentMonthSpending - previousMonthSpending
    }

    var monthlySpendingPercentChange: Double? {
        guard previousMonthSpending > 0 else { return nil }
        return monthlySpendingDifference / previousMonthSpending * 100
    }

    init(mangas: [Manga]) {
        let calendar = Calendar.current
        let unknownTitle = L("Nieznany tytuł")

        var totalSeries = 0
        var totalVolumes = 0
        var ownedVolumes = 0
        var readVolumes = 0
        var ownedPriceSum = 0.0
        var ownedPriceCount = 0
        var mangaSpend: [MangaSpendData] = []
        var mangaProgress: [MangaProgressData] = []
        var purchasesByMonth: [Date: (count: Int, amount: Double)] = [:]
        var itemsByReadDay: [Date: [String]] = [:]

        for manga in mangas {
            let isSold = manga.isSold ?? false
            let isPlanned = manga.isPlanned ?? false
            if !isSold, !isPlanned, !(manga.isSpinOff ?? false) {
                totalSeries += 1
            }

            var spent = 0.0
            var read = 0
            let volumes = manga.volumes

            for volume in volumes {
                let isRead = volume.read == true
                if isRead {
                    read += 1
                }
                if volume.owned {
                    if let price = volume.price {
                        spent += price
                    }
                    if let purchaseDate = volume.purchaseDate {
                        let month = calendar.date(
                            from: calendar.dateComponents([.year, .month], from: purchaseDate)
                        ) ?? .now
                        purchasesByMonth[month, default: (0, 0)].count += 1
                        purchasesByMonth[month, default: (0, 0)].amount += volume.price ?? 0
                    }
                }
                if let readDate = volume.readDate {
                    let day = calendar.startOfDay(for: readDate)
                    let title = volume.manga?.title ?? unknownTitle
                    itemsByReadDay[day, default: []].append("\(title) #\(volume.number)")
                }
                if !isSold, !isPlanned {
                    totalVolumes += 1
                    if volume.owned {
                        ownedVolumes += 1
                        if let price = volume.price {
                            ownedPriceSum += price
                            ownedPriceCount += 1
                        }
                    }
                    if isRead {
                        readVolumes += 1
                    }
                }
            }

            if spent > 0 {
                mangaSpend.append(MangaSpendData(id: manga.persistentModelID, title: manga.title, amount: spent))
            }
            let percent = volumes.isEmpty ? 0 : Double(read) / Double(volumes.count) * 100
            if !isPlanned, !volumes.isEmpty, percent < 100 {
                mangaProgress.append(MangaProgressData(
                    id: manga.persistentModelID,
                    title: manga.title,
                    totalVolumes: volumes.count,
                    readVolumes: read,
                    percent: percent
                ))
            }
        }

        self.totalSeries = totalSeries
        self.totalVolumes = totalVolumes
        self.ownedVolumes = ownedVolumes
        self.readVolumes = readVolumes
        averageVolumePrice = ownedPriceCount > 0 ? ownedPriceSum / Double(ownedPriceCount) : 0
        self.mangaSpend = mangaSpend.sorted { $0.amount > $1.amount }
        self.mangaProgress = mangaProgress.sorted { $0.percent > $1.percent }

        let monthlyPurchases = purchasesByMonth
            .map { MonthlyPurchaseData(month: $0.key, count: $0.value.count, amount: $0.value.amount) }
            .sorted { $0.month < $1.month }
        self.monthlyPurchases = monthlyPurchases

        readDays = itemsByReadDay
            .map { ReadDayData(date: $0.key, count: $0.value.count, items: $0.value.sorted()) }
            .sorted { $0.date < $1.date }
        readDayLookup = Dictionary(uniqueKeysWithValues: readDays.map { ($0.date, $0) })

        let now = Date()
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: now)
        func spending(in month: Date?) -> Double {
            guard let month else { return 0 }
            return monthlyPurchases.first {
                calendar.isDate($0.month, equalTo: month, toGranularity: .month)
            }?.amount ?? 0
        }
        currentMonthSpending = spending(in: now)
        previousMonthSpending = spending(in: previousMonth)
    }
}

// MARK: - Reading activity

/// Heatmap plus the list for the selected day. Owns the selection so
/// clicking a cell doesn't re-derive the dashboard's data.
private struct ReadingActivityCard: View {
    let readDays: [ReadDayData]
    let readDayLookup: [Date: ReadDayData]

    @State private var selectedReadDay: ReadDayData?

    var body: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 16) {
                DetailCardTitle(title: "Aktywność czytania", systemImage: "flame.fill")

                if readDays.isEmpty {
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
        .onAppear {
            if selectedReadDay == nil {
                selectedReadDay = readDays.last
            }
        }
        .onChange(of: readDays) { _, newValue in
            // Keep the selected day's list current after a volume is (un)marked.
            if let selected = selectedReadDay {
                selectedReadDay = newValue.first { $0.date == selected.date } ?? newValue.last
            }
        }
    }
}

// MARK: - Monthly spending

/// Bar chart with a hover tooltip. Owns the hover state so tracking the
/// mouse only re-renders this chart.
private struct MonthlySpendingCard: View {
    let monthlyPurchases: [MonthlyPurchaseData]

    @Environment(\.locale) private var locale
    @State private var hoveredPurchase: MonthlyPurchaseData?

    var body: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Wydatki miesięczne", systemImage: "creditcard.fill")

                if monthlyPurchases.isEmpty {
                    emptyNote("Ustaw daty zakupu tomów, aby zobaczyć wykres.")
                } else {
                    Chart {
                        ForEach(monthlyPurchases) { item in
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
                                        hoveredPurchase = monthlyPurchases.min {
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
}

// MARK: - Heatmap

private struct ReadHeatmapView: View {
    let readDayLookup: [Date: ReadDayData]
    @Binding var selectedDay: ReadDayData?

    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 6

    // The grid covers the last 42 weeks. Its days are laid out once here
    // rather than re-derived by every one of the ~300 cells.
    private let weekdaySymbols: [String]
    private let weeks: [[Date]]
    /// Cells before this day (leading days of the first week) stay blank.
    private let rangeStart: Date
    /// Cells after today (trailing days of the current week) stay blank.
    private let today: Date

    init(readDayLookup: [Date: ReadDayData], selectedDay: Binding<ReadDayData?>) {
        self.readDayLookup = readDayLookup
        _selectedDay = selectedDay

        let calendar = Calendar.current
        weekdaySymbols = calendar.shortWeekdaySymbols

        let today = calendar.startOfDay(for: Date())
        let rangeStart = calendar.date(byAdding: .weekOfYear, value: -41, to: today) ?? today
        let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: rangeStart)?.start ?? rangeStart
        let currentWeekEnd = calendar.dateInterval(of: .weekOfYear, for: today)?.end ?? today
        let lastDay = calendar.date(byAdding: .day, value: -1, to: currentWeekEnd) ?? today

        var days: [Date] = []
        var current = firstWeekStart
        while current <= lastDay, let next = calendar.date(byAdding: .day, value: 1, to: current) {
            days.append(current)
            current = next
        }

        self.today = today
        self.rangeStart = rangeStart
        weeks = stride(from: 0, to: days.count, by: 7).map {
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
        let isOutsideRange = day < rangeStart || day > today
        let readDay = readDayLookup[day]
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
                            selectedDay?.date == day ? .white.opacity(0.7) : .clear,
                            lineWidth: 1
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOutsideRange || readDay == nil)
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
