import AppKit
import Foundation

struct AniListMangaInfo {
    let id: Int
    let status: String?
    let genres: [String]
    let averageScore: Int?
    let startDate: Date?
    let endDate: Date?
    let coverURL: String?
    let author: String?
    let description: String?
    let bannerImage: String?
}

struct AniListService {
    struct Response: Decodable {
        let data: DataContainer?

        struct DataContainer: Decodable {
            let Media: Media?
        }

        struct Media: Decodable {
            let coverImage: CoverImage?
        }

        struct CoverImage: Decodable {
            let extraLarge: String?
            let large: String?
            let medium: String?
        }
    }

    static func fetchMangaCoverURL(title: String) async throws -> String? {
        let query = """
            query ($search: String) {
              Media(search: $search, type: MANGA) {
                coverImage {
                  extraLarge
                  large
                  medium
                }
              }
            }
            """

        let body: [String: Any] = [
            "query": query,
            "variables": [
                "search": title
            ],
        ]

        let url = URL(string: "https://graphql.anilist.co")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)

        return decoded.data?.Media?.coverImage?.extraLarge
            ?? decoded.data?.Media?.coverImage?.large
            ?? decoded.data?.Media?.coverImage?.medium
    }

    static func fetchMangaInfo(title: String) async throws -> AniListMangaInfo?
    {
        let query = """
            query ($search: String) {
              Page(page: 1, perPage: 10) {
                media(search: $search, type: MANGA, sort: SEARCH_MATCH) {
                  id
                  status
                  genres
                  averageScore
                  description
                  bannerImage
                  format
                  title {
                    romaji
                    english
                    native
                  }
                  startDate {
                    year
                    month
                    day
                  }
                  endDate {
                    year
                    month
                    day
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                  }
                  staff {
                    edges {
                      role
                      node {
                        id
                        name {
                          full
                        }
                      }
                    }
                  }
                }
              }
            }
            """

        let body: [String: Any] = [
            "query": query,
            "variables": [
                "search": title
            ],
        ]

        let url = URL(string: "https://graphql.anilist.co")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(
            AniListInfoResponse.self,
            from: data
        )

        guard let results = decoded.data?.Page?.media, !results.isEmpty else {
            return nil
        }

        let normalizedSearch = normalizeTitle(title)

        let media =
            results.first(where: { item in
                item.format == "MANGA"
                    && [
                        item.title?.english,
                        item.title?.romaji,
                        item.title?.native,
                    ]
                    .compactMap { $0 }
                    .contains(where: { normalizeTitle($0) == normalizedSearch })
            })
            ?? results.first(where: { $0.format == "MANGA" })
            ?? results[0]
        let coverURL =
            media.coverImage?.extraLarge
            ?? media.coverImage?.large
            ?? media.coverImage?.medium

        let mainAuthor = media.staff?.edges?
            .first(where: {
                $0.role.contains("Story") || $0.role.contains("Art")
            })?
            .node
            .name
            .full

        return AniListMangaInfo(
            id: media.id,
            status: media.status,
            genres: media.genres ?? [],
            averageScore: media.averageScore,
            startDate: media.startDate?.date,
            endDate: media.endDate?.date,
            coverURL: coverURL,
            author: mainAuthor,
            description: plainText(from: media.description),
            bannerImage: media.bannerImage
        )
    }

    private static func plainText(from html: String?) -> String? {
        guard let html, !html.isEmpty else { return nil }

        let data = Data(html.utf8)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]

        guard
            let attributed = try? NSAttributedString(
                data: data,
                options: options,
                documentAttributes: nil
            )
        else {
            return html
        }

        let trimmed = attributed.string.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizeTitle(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AniListInfoResponse: Decodable {
    let data: DataContainer?

    struct DataContainer: Decodable {
        let Page: Page?
    }

    struct Page: Decodable {
        let media: [Media]?
    }

    struct Media: Decodable {
        let id: Int
        let status: String?
        let genres: [String]?
        let averageScore: Int?
        let startDate: AniListDate?
        let endDate: AniListDate?
        let coverImage: CoverImage?
        let staff: Staff?
        let description: String?
        let bannerImage: String?
        let format: String?
        let title: MediaTitle?
    }

    struct MediaTitle: Decodable {
        let romaji: String?
        let english: String?
        let native: String?
    }

    struct CoverImage: Decodable {
        let extraLarge: String?
        let large: String?
        let medium: String?
    }

    struct Staff: Decodable {
        let edges: [StaffEdge]?
    }

    struct StaffEdge: Decodable {
        let role: String
        let node: StaffNode
    }

    struct StaffNode: Decodable {
        let id: Int
        let name: StaffName
    }

    struct StaffName: Decodable {
        let full: String?
    }

    struct AniListDate: Decodable {
        let year: Int?
        let month: Int?
        let day: Int?

        var date: Date? {
            guard let year else { return nil }

            var components = DateComponents()
            components.year = year
            components.month = month ?? 1
            components.day = day ?? 1

            return Calendar.current.date(from: components)
        }
    }
}
