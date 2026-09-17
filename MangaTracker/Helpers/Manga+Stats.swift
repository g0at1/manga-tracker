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
