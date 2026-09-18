import Foundation

extension Manga {
    var ownedVolumesCount: Int {
        volumes.filter { $0.owned }.count
    }

    var totalPaid: Double {
        volumes
            .filter { $0.owned }
            .compactMap { $0.price }
            .reduce(0, +)
    }

    var readPercent: Double {
        guard !volumes.isEmpty else { return 0 }
        let readCount = volumes.filter { $0.read == true }.count
        return Double(readCount) / Double(volumes.count) * 100
    }
}

extension Manga {
    var readVolumesCount: Int {
        volumes.filter { $0.read == true }.count
    }

    /// Every volume read and the series itself finished on AniList.
    var isCompleted: Bool {
        !volumes.isEmpty
            && volumes.allSatisfy { $0.read == true }
            && aniListStatus == "FINISHED"
    }

    /// Lowest-numbered owned volume that hasn't been read yet.
    var nextUnreadVolume: Volume? {
        volumes
            .filter { $0.owned && $0.read != true }
            .min { $0.number < $1.number }
    }

    /// When the most recently read volume was finished.
    var lastReadDate: Date? {
        volumes.compactMap(\.readDate).max()
    }
}
