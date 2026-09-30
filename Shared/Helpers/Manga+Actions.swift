import Foundation

extension Manga {
    /// Marks the volume after the highest-numbered read one as read, dated
    /// now — or, when that volume is split, just its next unread part.
    /// Does nothing when there is no such volume or it's already read.
    func markNextAsRead() {
        let sortedVolumes = volumes.sorted { $0.number < $1.number }
        let lastReadIndex = sortedVolumes.lastIndex(where: { $0.read == true }) ?? -1
        let nextIndex = lastReadIndex + 1
        guard sortedVolumes.indices.contains(nextIndex) else { return }

        let nextVolume = sortedVolumes[nextIndex]
        guard nextVolume.read != true else { return }
        if let part = nextVolume.firstUnreadPart {
            nextVolume.markPart(part, read: true)
        } else {
            nextVolume.read = true
            nextVolume.readDate = Date()
        }
    }
}

extension Manga {
    /// Volumes ordered and not yet arrived, by number.
    var volumesOnTheirWay: [Volume] {
        volumes.filter(\.isOnItsWay).sorted { $0.number < $1.number }
    }

    /// The order arrived: every volume on its way becomes owned, keeping
    /// its order date. Returns how many were marked.
    @discardableResult
    func markOrderDelivered(on date: Date = .now) -> Int {
        let arriving = volumesOnTheirWay
        for volume in arriving {
            volume.markOwned(true, on: date)
        }
        return arriving.count
    }
}
