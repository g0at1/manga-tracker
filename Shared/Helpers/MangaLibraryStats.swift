import Foundation

/// Library-wide numbers for the header tiles, computed in a single pass
/// over every series and volume. Sold series and the wishlist are left
/// out of the collection numbers; read days count from everything.
struct MangaLibraryStats {
    /// Series that aren't sold, planned or spin-offs.
    let mangaCount: Int
    /// Owned volumes across unsold series.
    let ownedVolumesCount: Int
    /// Spent on owned volumes across unsold series.
    let totalPaid: Double
    /// Share of owned volumes (unsold series) that have been read, counting
    /// a split volume part by part.
    let totalReadPercent: Double
    let didReadToday: Bool
    let currentReadStreak: Int

    init(mangas: [Manga]) {
        let calendar = Calendar.current
        var mangaCount = 0
        var ownedCount = 0
        var ownedUnits = 0
        var ownedReadUnits = 0
        var totalPaid: Double = 0
        var readDays = Set<Date>()

        for manga in mangas {
            let isExcluded = (manga.isSold ?? false) || (manga.isPlanned ?? false)
            if !isExcluded, !(manga.isSpinOff ?? false) {
                mangaCount += 1
            }
            for volume in manga.volumes {
                for readDate in volume.readDates {
                    readDays.insert(calendar.startOfDay(for: readDate))
                }
                guard !isExcluded, volume.owned else { continue }
                ownedCount += 1
                totalPaid += volume.price ?? 0
                ownedUnits += volume.unitCount
                ownedReadUnits += volume.readUnitCount
            }
        }

        self.mangaCount = mangaCount
        ownedVolumesCount = ownedCount
        self.totalPaid = totalPaid
        totalReadPercent = ownedUnits > 0 ? Double(ownedReadUnits) / Double(ownedUnits) * 100 : 0

        let today = calendar.startOfDay(for: Date())
        didReadToday = readDays.contains(today)
        currentReadStreak = Self.streak(readDays: readDays, today: today, calendar: calendar)
    }

    /// Consecutive days with a read volume, ending today or yesterday.
    private static func streak(readDays: Set<Date>, today: Date, calendar: Calendar) -> Int {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var day: Date
        if readDays.contains(today) {
            day = today
        } else if readDays.contains(yesterday) {
            day = yesterday
        } else {
            return 0
        }

        var streak = 0
        while readDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}
