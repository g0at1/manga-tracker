import Foundation
import SwiftData

// The owned/read rules every screen shares. A read volume is an owned one;
// un-owning clears reading; dates are stamped when a status is first set
// and cleared when it's taken away. Parts follow the same rules through
// their volume.

extension Volume {
    var isSplit: Bool {
        !parts.isEmpty
    }

    var sortedParts: [VolumePart] {
        parts.sorted { $0.index < $1.index }
    }

    var readPartCount: Int {
        parts.filter(\.read).count
    }

    /// How much reading the volume represents: each part of a split volume,
    /// otherwise the volume itself.
    var unitCount: Int {
        max(parts.count, 1)
    }

    var readUnitCount: Int {
        isSplit ? readPartCount : (read == true ? 1 : 0)
    }

    /// Lowest-indexed part not read yet; `nil` for an unsplit volume.
    var firstUnreadPart: VolumePart? {
        sortedParts.first { !$0.read }
    }

    /// Days something was finished, for the activity numbers: each part of
    /// a split volume (the volume's own date repeats the last part's),
    /// otherwise the volume.
    var readDates: [Date] {
        isSplit ? parts.compactMap(\.readDate) : readDate.map { [$0] } ?? []
    }

    func markOwned(_ owned: Bool, on date: Date = .now) {
        if owned {
            self.owned = true
            if purchaseDate == nil {
                purchaseDate = date
            }
        } else {
            self.owned = false
            purchaseDate = nil
            markRead(false)
        }
    }

    /// The whole volume: every part along with it.
    func markRead(_ read: Bool, on date: Date = .now) {
        if read {
            markOwned(true, on: date)
            self.read = true
            if readDate == nil {
                readDate = date
            }
            for part in parts where !part.read {
                part.read = true
                part.readDate = date
            }
        } else {
            self.read = false
            readDate = nil
            for part in parts {
                part.read = false
                part.readDate = nil
            }
        }
    }

    /// What "read the next thing" means for this volume: its first unread
    /// part when split, otherwise the volume itself.
    func markNextUnitRead(on date: Date = .now) {
        if let part = firstUnreadPart {
            markPart(part, read: true, on: date)
        } else {
            markRead(true, on: date)
        }
    }

    /// One part; the volume counts as read once its last part is.
    func markPart(_ part: VolumePart, read: Bool, on date: Date = .now) {
        part.read = read
        part.readDate = read ? part.readDate ?? date : nil
        if read {
            markOwned(true, on: date)
        }
        refreshReadFromParts()
    }

    /// Splits the volume into `count` parts, or joins it back for a count
    /// of one. Parts already there keep their state; new ones start out as
    /// read as the volume is, so splitting a finished volume leaves it
    /// finished.
    func setPartCount(_ count: Int) {
        let count = max(count, 1)
        let current = sortedParts
        if count == 1 {
            removeParts(current)
            return
        }

        let inheritedRead = read == true
        let nextIndex = (current.last?.index ?? 0) + 1
        if nextIndex <= count {
            for index in nextIndex ... count {
                parts.append(VolumePart(index: index, read: inheritedRead, readDate: inheritedRead ? readDate : nil, volume: self))
            }
        }
        removeParts(current.filter { $0.index > count })
        refreshReadFromParts()
    }

    private func removeParts(_ removed: [VolumePart]) {
        guard !removed.isEmpty else { return }
        let removedIDs = Set(removed.map(\.persistentModelID))
        parts.removeAll { removedIDs.contains($0.persistentModelID) }
        for part in removed {
            part.modelContext?.delete(part)
        }
    }

    /// Derives `read`/`readDate` from the parts of a split volume: read
    /// once every part is, dated when the last one was finished. Call after
    /// editing a part directly (its date, say).
    func refreshReadFromParts() {
        guard isSplit else { return }
        if parts.allSatisfy(\.read) {
            read = true
            readDate = parts.compactMap(\.readDate).max() ?? readDate ?? .now
        } else {
            read = false
            readDate = nil
        }
    }
}
