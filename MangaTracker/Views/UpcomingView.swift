import AppKit
import SwiftData
import SwiftUI

/// Upcoming volume releases as a timeline grouped by month.
struct UpcomingView: View {
    let mangas: [Manga]

    @Environment(\.locale) private var locale
    @State private var editingBuyTarget: Volume?

    var body: some View {
        // Built once per render; every section below reads from it.
        let schedule = UpcomingSchedule(mangas: mangas)

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                header
                tiles(schedule)

                if schedule.entries.isEmpty {
                    DetailCard {
                        ContentUnavailableView(
                            "Brak nadchodzących tomów",
                            systemImage: "calendar.badge.clock",
                            description: Text("Ustaw datę premiery w szczegółach tomu, aby pojawił się na tej liście.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
                    }
                } else {
                    ForEach(schedule.months, id: \.month) { group in
                        monthCard(group.month, entries: group.entries)
                    }
                }
            }
            .padding(28)
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(AppBackgroundView())
        .navigationTitle("Nadchodzące")
        .onAppear {
            WindowManager.ensureComfortableSize(windowID: "upcoming", minWidth: 1100, minHeight: 820)
        }
        .sheet(item: $editingBuyTarget) { volume in
            BuyLinkEditorSheet(volume: volume)
        }
    }

    // MARK: - Header & tiles

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nadchodzące")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Zobacz co wychodzi i kiedy")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func tiles(_ schedule: UpcomingSchedule) -> some View {
        HStack(spacing: 12) {
            StatCardView(
                title: "najbliższa premiera",
                value: schedule.entries.first.map { $0.releaseDate.yyyyMMdd() } ?? "—",
                systemImage: "calendar.badge.clock",
                accentColor: .green
            )
            StatCardView(
                title: "w ciągu 30 dni",
                value: "\(schedule.within30Days)",
                systemImage: "clock.fill",
                accentColor: .orange
            )
            StatCardView(
                title: "wszystkich premier",
                value: "\(schedule.entries.count)",
                systemImage: "square.stack.3d.up.fill",
                accentColor: .blue
            )
            StatCardView(
                title: "z linkiem do zakupu",
                value: "\(schedule.withBuyLink)",
                systemImage: "cart.fill",
                accentColor: .teal
            )
            Spacer(minLength: 0)
        }
    }

    // MARK: - Month card

    private func monthCard(_ month: Date, entries: [UpcomingVolume]) -> some View {
        DetailCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(month.formatted(.dateTime.month(.wide).year().locale(locale)).capitalized)
                        .font(.headline)
                    Text("\(entries.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                Divider().overlay(Color.white.opacity(0.06))

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    UpcomingRow(entry: entry, isAlternate: index.isMultiple(of: 2)) {
                        editingBuyTarget = entry.volume
                    }
                }
            }
        }
    }
}

// MARK: - Schedule

/// Every volume with a release date from today on, sorted by date, then
/// title, then number, plus the numbers for the header tiles. Built in one
/// pass over the library.
private struct UpcomingSchedule {
    let entries: [UpcomingVolume]
    /// Releases bucketed by month, in chronological order.
    let months: [(month: Date, entries: [UpcomingVolume])]
    let within30Days: Int
    let withBuyLink: Int

    init(mangas: [Manga]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let in30Days = calendar.date(byAdding: .day, value: 30, to: Date())

        var entries: [UpcomingVolume] = []
        for manga in mangas {
            for volume in manga.volumes {
                guard let releaseDate = volume.releaseDate, releaseDate >= today else { continue }
                entries.append(UpcomingVolume(manga: manga, volume: volume, releaseDate: releaseDate, today: today, calendar: calendar))
            }
        }
        entries.sort { lhs, rhs in
            if lhs.releaseDate != rhs.releaseDate {
                return lhs.releaseDate < rhs.releaseDate
            }
            if lhs.manga.title != rhs.manga.title {
                return lhs.manga.title.localizedCaseInsensitiveCompare(rhs.manga.title) == .orderedAscending
            }
            return lhs.volume.number < rhs.volume.number
        }

        self.entries = entries
        within30Days = in30Days.map { end in entries.filter { $0.releaseDate <= end }.count } ?? entries.count
        withBuyLink = entries.filter { $0.buyURL != nil }.count

        let grouped = Dictionary(grouping: entries) { entry in
            calendar.date(from: calendar.dateComponents([.year, .month], from: entry.releaseDate)) ?? entry.releaseDate
        }
        months = grouped.keys.sorted().map { (month: $0, entries: grouped[$0] ?? []) }
    }
}

// MARK: - Row

private struct UpcomingVolume: Identifiable {
    let manga: Manga
    let volume: Volume
    let releaseDate: Date
    let buyURL: URL?
    let daysUntil: Int

    var id: PersistentIdentifier {
        volume.persistentModelID
    }

    init(manga: Manga, volume: Volume, releaseDate: Date, today: Date, calendar: Calendar) {
        self.manga = manga
        self.volume = volume
        self.releaseDate = releaseDate
        buyURL = volume.buyURL
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(string: $0) }
        daysUntil = calendar.dateComponents(
            [.day],
            from: today,
            to: calendar.startOfDay(for: releaseDate)
        ).day ?? 0
    }
}

/// `RelativeDateTimeFormatter` is costly to set up, so one is kept per
/// locale for all the rows.
@MainActor
private enum RelativeFormatters {
    private static var cache: [String: RelativeDateTimeFormatter] = [:]

    static func formatter(for locale: Locale) -> RelativeDateTimeFormatter {
        if let cached = cache[locale.identifier] {
            return cached
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        cache[locale.identifier] = formatter
        return formatter
    }
}

private struct UpcomingRow: View {
    let entry: UpcomingVolume
    let isAlternate: Bool
    let onEditBuyURL: () -> Void

    @Environment(\.locale) private var locale
    @State private var isHovered = false

    private var isSoon: Bool {
        entry.daysUntil <= 30
    }

    var body: some View {
        HStack(spacing: 14) {
            Color.clear
                .frame(width: 46, height: 66)
                .overlay(
                    CoverImageView(url: URL(string: entry.manga.coverURL ?? ""), cornerRadius: 8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.manga.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("Tom #\(entry.volume.number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.releaseDate.yyyyMMdd())
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                Text(relativeText)
                    .font(.caption.weight(isSoon ? .semibold : .regular))
                    .foregroundStyle(isSoon ? Color.green : .secondary)
            }
            .frame(width: 130, alignment: .trailing)

            if let url = entry.buyURL {
                SubtleButton(title: "Kup", systemImage: "cart", tint: .green) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                SubtleButton(title: "Dodaj link", systemImage: "link.badge.plus", tint: .secondary, action: onEditBuyURL)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            isHovered ? Color.white.opacity(0.05) : Color.white.opacity(isAlternate ? 0.025 : 0)
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            if let url = entry.buyURL {
                Button("Otwórz link zakupu") { NSWorkspace.shared.open(url) }
                Divider()
            }
            Button("Edytuj link zakupu", action: onEditBuyURL)
            Button("Skopiuj tytuł") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    L("%@ — tom %lld", entry.manga.title, entry.volume.number),
                    forType: .string
                )
            }
        }
    }

    private var relativeText: String {
        RelativeFormatters.formatter(for: locale)
            .localizedString(for: entry.releaseDate, relativeTo: Date())
    }
}

// MARK: - Buy link sheet

private struct BuyLinkEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var volume: Volume

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailCardTitle(title: "Link do zakupu", systemImage: "cart")

            TextField(
                "https://…",
                text: Binding(
                    get: { volume.buyURL ?? "" },
                    set: { volume.buyURL = $0.isEmpty ? nil : $0 }
                )
            )
            .detailInput()

            HStack {
                SubtleButton(title: "Usuń link", systemImage: "trash", tint: .red) {
                    volume.buyURL = nil
                    dismiss()
                }
                Spacer()
                Button("Anuluj", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Gotowe") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(AppBackgroundView())
    }
}
