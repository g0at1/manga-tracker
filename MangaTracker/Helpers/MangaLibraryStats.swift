import Foundation

struct MangaLibraryStats {
    let mangas: [Manga]

    var mangaCount: Int {
        mangas.count
    }

    var ownedVolumesCount: Int {
        mangas.flatMap { $0.volumes }.filter { $0.owned }.count
    }

    var totalPaid: Double {
        mangas
            .flatMap { $0.volumes }
            .filter { $0.owned }
            .compactMap { $0.price }
            .reduce(0, +)
    }

    var totalReadPercent: Double {
        let ownedVolumes =
            mangas
            .flatMap { $0.volumes }
            .filter { $0.owned }

        guard !ownedVolumes.isEmpty else { return 0 }

        let readCount = ownedVolumes.filter { $0.read == true }.count
        return (Double(readCount) / Double(ownedVolumes.count)) * 100
    }

    var didReadToday: Bool {
        let calendar = Calendar.current

        return
            mangas
            .flatMap { $0.volumes }
            .compactMap { $0.readDate }
            .contains { calendar.isDateInToday($0) }
    }

    var currentReadStreak: Int {
        let calendar = Calendar.current

        let readDays = Array(
            Set(
                mangas
                    .flatMap { $0.volumes }
                    .compactMap { $0.readDate }
                    .map { calendar.startOfDay(for: $0) }
            )
        ).sorted(by: >)

        guard let firstDay = readDays.first else { return 0 }

        var streak = 1
        var expectedDay = firstDay

        for day in readDays.dropFirst() {
            guard
                let previousDay = calendar.date(
                    byAdding: .day,
                    value: -1,
                    to: expectedDay
                )
            else {
                break
            }

            if calendar.isDate(day, inSameDayAs: previousDay) {
                streak += 1
                expectedDay = previousDay
            } else if day < previousDay {
                break
            }
        }

        return streak
    }
}
