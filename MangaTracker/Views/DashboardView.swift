import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    let mangas: [Manga]
    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summaryCards

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
