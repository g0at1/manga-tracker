import Foundation

/// Per-volume cover art, which AniList doesn't serve — it only knows the
/// series. MangaDex does, and it stores the AniList id of every series it
/// carries (`links.al`), so a series already refreshed from AniList can be
/// matched exactly instead of by title.
///
/// Covers are uploaded per language. English editions aren't always there
/// (Berserk and One Piece have none), while the Japanese ones are complete
/// for practically every series, so the locale preference below falls back
/// to `ja` rather than giving up.
enum MangaDexService {
    private static let apiBase = "https://api.mangadex.org"
    private static let uploadsBase = "https://uploads.mangadex.org/covers"

    /// Which edition's cover to prefer when a volume has several.
    private static let localePreference = ["en", "ja"]

    /// MangaDex asks clients to identify themselves and rejects unnamed ones.
    private static let userAgent = "MangaTracker/1.0 (+https://github.com/g0at1/manga-tracker)"

    /// Cover files come in three widths; 512px is wider than the largest a
    /// volume thumbnail is ever drawn, and a quarter the bytes of the
    /// original (≈160 KB against ≈650 KB).
    private static let thumbnailSuffix = ".512.jpg"

    /// Most series are well under this; Berserk, with every language's
    /// covers, is the widest at 118. Paged for anyway.
    private static let coverPageSize = 100
    private static let coverPageLimit = 5

    enum ServiceError: Error {
        case seriesNotFound
    }

    /// One uploaded cover, as MangaDex describes it. `volume` is a string
    /// because the API numbers side stories fractionally ("7.5") and files
    /// loose chapters under "none".
    struct CoverEntry {
        let volume: String?
        let fileName: String
        let locale: String?
    }

    // MARK: - Series lookup

    /// The MangaDex id for a series. `aniListId` makes this exact: the
    /// search is still by title, but only a result pointing back at the same
    /// AniList entry is accepted. Without one the best title match is taken,
    /// which is the same guess `AniListService` makes.
    static func resolveSeriesID(title: String, aniListId: Int?) async throws -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents(string: "\(apiBase)/manga")!
        components.queryItems = [
            URLQueryItem(name: "title", value: trimmed),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "contentRating[]", value: "safe"),
            URLQueryItem(name: "contentRating[]", value: "suggestive"),
            URLQueryItem(name: "contentRating[]", value: "erotica"),
            URLQueryItem(name: "contentRating[]", value: "pornographic"),
        ]

        let response: MangaSearchResponse = try await get(components.url!)
        let results = response.data ?? []
        guard !results.isEmpty else { return nil }

        if let aniListId {
            // The AniList id is stored as a string, and a handful of entries
            // pad it or wrap it in a URL, so compare the digits.
            let wanted = String(aniListId)
            return results.first { entry in
                entry.attributes?.links?.al.map { digits(in: $0) == wanted } ?? false
            }?.id
        }

        let normalized = normalize(trimmed)
        return results.first { entry in
            (entry.attributes?.title.values.contains { normalize($0) == normalized } ?? false)
                || (entry.attributes?.altTitles?.contains { $0.values.contains { normalize($0) == normalized } } ?? false)
        }?.id ?? results[0].id
    }

    // MARK: - Covers

    /// Every volume's cover for a series, keyed by volume number. Volumes
    /// MangaDex numbers fractionally (`7.5` side stories) are skipped —
    /// the library has no row to hang them on.
    static func fetchVolumeCovers(seriesID: String) async throws -> [Int: String] {
        var entries: [CoverEntry] = []
        var offset = 0

        for _ in 0 ..< coverPageLimit {
            var components = URLComponents(string: "\(apiBase)/cover")!
            components.queryItems = [
                URLQueryItem(name: "manga[]", value: seriesID),
                URLQueryItem(name: "limit", value: String(coverPageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "order[volume]", value: "asc"),
            ]

            let response: CoverListResponse = try await get(components.url!)
            let page = response.data ?? []
            guard !page.isEmpty else { break }

            entries += page.compactMap { cover in
                cover.attributes.map {
                    CoverEntry(volume: $0.volume, fileName: $0.fileName, locale: $0.locale)
                }
            }

            offset += page.count
            if offset >= (response.total ?? offset) {
                break
            }
        }

        return bestCoverURLs(seriesID: seriesID, from: entries)
    }

    /// Picks one cover per volume out of everything uploaded for a series:
    /// the most preferred locale wins, and volumes the library has no row
    /// for — fractional ones, and loose chapters — are dropped.
    static func bestCoverURLs(seriesID: String, from entries: [CoverEntry]) -> [Int: String] {
        var best: [Int: (fileName: String, rank: Int)] = [:]

        for entry in entries {
            guard let number = volumeNumber(from: entry.volume) else { continue }
            let rank = localeRank(entry.locale)
            // Lower rank wins; a tie keeps the first, which the `volume`
            // ordering makes deterministic across runs.
            if let existing = best[number], existing.rank <= rank {
                continue
            }
            best[number] = (entry.fileName, rank)
        }

        return best.mapValues { coverURL(seriesID: seriesID, fileName: $0.fileName) }
    }

    /// Where a cover file is served from, at thumbnail width.
    static func coverURL(seriesID: String, fileName: String) -> String {
        "\(uploadsBase)/\(seriesID)/\(fileName)\(thumbnailSuffix)"
    }

    /// Resolves the series if it hasn't been already, then fetches its
    /// covers. Returns the covers and the id to cache, so the search is
    /// paid for once per series rather than once per refresh.
    static func fetchVolumeCovers(
        title: String,
        aniListId: Int?,
        knownSeriesID: String?
    ) async throws -> (seriesID: String, covers: [Int: String]) {
        let seriesID: String
        if let knownSeriesID, !knownSeriesID.isEmpty {
            seriesID = knownSeriesID
        } else if let resolved = try await resolveSeriesID(title: title, aniListId: aniListId) {
            seriesID = resolved
        } else {
            throw ServiceError.seriesNotFound
        }

        return try (seriesID, await fetchVolumeCovers(seriesID: seriesID))
    }

    // MARK: - Helpers

    private static func localeRank(_ locale: String?) -> Int {
        guard let locale else { return localePreference.count }
        return localePreference.firstIndex(of: locale) ?? localePreference.count
    }

    /// `"7"` → 7, `"7.5"` and `""` → nil. MangaDex also files loose chapters
    /// under volume `"none"`, which parses to nil on its own.
    private static func volumeNumber(from raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        return Int(raw)
    }

    private static func digits(in value: String) -> String {
        value.filter(\.isNumber)
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Responses

private struct MangaSearchResponse: Decodable {
    let data: [Entry]?

    struct Entry: Decodable {
        let id: String
        let attributes: Attributes?
    }

    struct Attributes: Decodable {
        let title: [String: String]
        let altTitles: [[String: String]]?
        let links: Links?
    }

    struct Links: Decodable {
        let al: String?
    }
}

private struct CoverListResponse: Decodable {
    let data: [Entry]?
    let total: Int?

    struct Entry: Decodable {
        let id: String
        let attributes: Attributes?
    }

    struct Attributes: Decodable {
        let volume: String?
        let fileName: String
        let locale: String?
    }
}
