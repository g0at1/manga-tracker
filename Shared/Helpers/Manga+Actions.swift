import Foundation

extension Manga {
    /// Marks the volume after the highest-numbered read one as read, dated
    /// now. Does nothing when there is no such volume or it's already read.
    func markNextAsRead() {
        let sortedVolumes = volumes.sorted { $0.number < $1.number }
        let lastReadIndex = sortedVolumes.lastIndex(where: { $0.read == true }) ?? -1
        let nextIndex = lastReadIndex + 1
        guard sortedVolumes.indices.contains(nextIndex) else { return }

        let nextVolume = sortedVolumes[nextIndex]
        guard nextVolume.read != true else { return }
        nextVolume.read = true
        nextVolume.readDate = Date()
    }
}
