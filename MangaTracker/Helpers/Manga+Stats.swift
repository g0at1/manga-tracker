import Foundation

/// Everything the UI derives from a series' volumes, gathered in one pass so
/// a view doesn't walk the relationship once per number it shows.
struct MangaVolumeStats {
    var total = 0
    var owned = 0
    var read = 0
    /// Sum of the prices of owned volumes.
    var totalPaid: Double = 0
    /// Lowest-numbered owned volume that hasn't been read yet.
    var nextUnread: Volume?
    /// Lowest-numbered volume that isn't owned yet.
    var firstMissing: Volume?
    /// When the most recently read volume was finished.
    var lastReadDate: Date?

    var readPercent: Double {
        total > 0 ? Double(read) / Double(total) * 100 : 0
    }

    var ownsAnything: Bool {
        owned > 0
    }

    var hasMissing: Bool {
        owned < total
    }

    var allRead: Bool {
        total > 0 && read == total
    }
}

extension Manga {
    var volumeStats: MangaVolumeStats {
        var stats = MangaVolumeStats()
        for volume in volumes {
            stats.total += 1
            let isRead = volume.read == true
            if isRead {
                stats.read += 1
            }
            if volume.owned {
                stats.owned += 1
                stats.totalPaid += volume.price ?? 0
                if !isRead, volume.number < (stats.nextUnread?.number ?? .max) {
                    stats.nextUnread = volume
                }
            } else if volume.number < (stats.firstMissing?.number ?? .max) {
                stats.firstMissing = volume
            }
            if let readDate = volume.readDate, readDate > (stats.lastReadDate ?? .distantPast) {
                stats.lastReadDate = readDate
            }
        }
        return stats
    }

    /// Every volume read and the series itself finished on AniList.
    func isCompleted(_ stats: MangaVolumeStats) -> Bool {
        stats.allRead && aniListStatus == "FINISHED"
    }
}
