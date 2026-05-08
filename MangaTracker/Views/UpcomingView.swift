import SwiftUI

struct UpcomingView: View {
    let mangas: [Manga]
    @Environment(\.dismiss) private var dismiss

    private var upcomingVolumes: [UpcomingVolume] {
        let now = Calendar.current.startOfDay(for: Date())

        return mangas.flatMap { manga in
            manga.volumes.compactMap { volume -> UpcomingVolume? in
                guard let releaseDate = volume.releaseDate else { return nil }
                guard releaseDate >= now else { return nil }

                return UpcomingVolume(
                    manga: manga,
                    volume: volume,
                    releaseDate: releaseDate
                )
            }
        }
        .sorted { lhs, rhs in
            if lhs.releaseDate != rhs.releaseDate {
                return lhs.releaseDate < rhs.releaseDate
            }
            if lhs.manga.title != rhs.manga.title {
                return lhs.manga.title.localizedCaseInsensitiveCompare(
                    rhs.manga.title
                ) == .orderedAscending
            }
            return lhs.volume.number < rhs.volume.number
        }
    }

    private var next30Days: [UpcomingVolume] {
        guard
            let end = Calendar.current.date(
                byAdding: .day,
                value: 30,
                to: Date()
            )
        else {
            return upcomingVolumes
        }
        return upcomingVolumes.filter { $0.releaseDate <= end }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    upcomingHeader

                    if upcomingVolumes.isEmpty {
                        ContentUnavailableView(
                            "Brak nadchodzących tomów",
                            systemImage: "calendar.badge.clock",
                            description: Text(
                                "Ustaw datę premiery w szczegółach tomu, aby pojawił się na tej liście."
                            )
                        )
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        upcomingSection(
                            title: "Następne 30 dni",
                            subtitle: "Premiery w najbliższym miesiącu",
                            volumes: next30Days
                        )

                        upcomingSection(
                            title: "Wszystkie nadchodzące",
                            subtitle: "Pełna lista zaplanowanych premier",
                            volumes: upcomingVolumes
                        )
                    }
                }
                .padding(24)
            }
            .navigationTitle("Nadchodzące")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 720)
    }

    private var upcomingHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2.weight(.bold))
                .foregroundStyle(.green)
                .padding(12)
                .background(
                    .green.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text("Premiery tomów")
                    .font(.title2.weight(.bold))
                Text("Zobacz co wychodzi i kiedy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
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

    private func upcomingSection(
        title: String,
        subtitle: String,
        volumes: [UpcomingVolume]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.weight(.bold))

                Text("(\(volumes.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if volumes.isEmpty {
                Text("Brak premier w tej sekcji")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(volumes) { entry in
                        UpcomingRow(entry: entry)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

private struct UpcomingVolume: Identifiable {
    let id = UUID()
    let manga: Manga
    let volume: Volume
    let releaseDate: Date
}

private struct UpcomingRow: View {
    let entry: UpcomingVolume

    var body: some View {
        HStack(spacing: 14) {
            CachedAsyncImage(
                url: URL(string: entry.manga.coverURL ?? ""),
                cornerRadius: 10
            )
            .frame(width: 54, height: 74)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.manga.title)
                    .font(.headline)
                    .lineLimit(1)

                Text("Tom #\(entry.volume.number)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(
                    entry.releaseDate.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
                )
                .font(.headline.weight(.bold))

                Text(entry.releaseDate.relativeFormatted())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

extension Date {
    fileprivate func relativeFormatted() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
