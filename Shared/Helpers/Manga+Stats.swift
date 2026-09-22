import Foundation

/// Everything the UI derives from a series' volumes, gathered in one pass so
/// a view doesn't walk the relationship once per number it shows.
struct MangaVolumeStats {
    var total = 0
    var owned = 0
    /// Volumes read cover to cover; a split volume counts once its last
    /// part is read.
    var read = 0
    /// Reading measured in parts: a split volume contributes each of its
    /// parts, any other volume one. What the progress bar shows.
    var totalUnits = 0
    var readUnits = 0
    /// Sum of the prices of owned volumes.
    var totalPaid: Double = 0
    /// Lowest-numbered owned volume that hasn't been read yet.
    var nextUnread: Volume?
    /// The part of `nextUnread` to pick up, when that volume is split.
    var nextUnreadPart: VolumePart?
    /// Lowest-numbered volume that isn't owned yet.
    var firstMissing: Volume?
    /// When the most recently read volume (or part) was finished.
    var lastReadDate: Date?

    var readPercent: Double {
        totalUnits > 0 ? Double(readUnits) / Double(totalUnits) * 100 : 0
    }

    var ownsAnything: Bool {
        owned > 0
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
            stats.totalUnits += volume.unitCount
            stats.readUnits += volume.readUnitCount
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
            for part in volume.parts {
                if let readDate = part.readDate, readDate > (stats.lastReadDate ?? .distantPast) {
                    stats.lastReadDate = readDate
                }
            }
        }
        stats.nextUnreadPart = stats.nextUnread?.firstUnreadPart
        return stats
    }

    /// Every volume read and the series itself finished on AniList.
    func isCompleted(_ stats: MangaVolumeStats) -> Bool {
        stats.allRead && aniListStatus == "FINISHED"
    }
}
