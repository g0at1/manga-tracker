import Foundation

extension Manga {
    /// Hangs the fetched covers on the volumes that already exist, matched by
    /// number. Like the series cover in `applyAniListInfo`, a cover already
    /// set is left alone unless `overwrite` says otherwise, so a hand-picked
    /// one survives a refresh. Returns how many volumes got a cover.
    @discardableResult
    func applyVolumeCovers(_ covers: [Int: String], overwrite: Bool = false) -> Int {
        var applied = 0
        for volume in volumes {
            guard let url = covers[volume.number] else { continue }
            if !overwrite, !(volume.coverURL ?? "").isEmpty {
                continue
            }
            guard volume.coverURL != url else { continue }
            volume.coverURL = url
            applied += 1
        }
        return applied
    }

    /// Whether any volume has a cover — what the volume list checks before
    /// making room for a cover column, so a library that has never fetched
    /// them looks exactly as it did.
    var hasVolumeCovers: Bool {
        volumes.contains { !($0.coverURL ?? "").isEmpty }
    }

    /// Fetches this series' volume covers from MangaDex and applies them,
    /// caching the resolved series id on the way. Returns how many volumes
    /// got one; throws what the service throws.
    @MainActor
    @discardableResult
    func fetchVolumeCovers(overwrite: Bool = false) async throws -> Int {
        let result = try await MangaDexService.fetchVolumeCovers(
            title: title,
            aniListId: aniListId,
            knownSeriesID: mangaDexId
        )
        mangaDexId = result.seriesID
        return applyVolumeCovers(result.covers, overwrite: overwrite)
    }
}
