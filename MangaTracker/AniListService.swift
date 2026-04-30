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
              Media(search: $search, type: MANGA) {
                id
                status
                genres
                averageScore
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

        guard let media = decoded.data?.Media else {
            return nil
        }

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
            author: mainAuthor
        )
    }
}

private struct AniListInfoResponse: Decodable {
    let data: DataContainer?

    struct DataContainer: Decodable {
        let Media: Media?
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
