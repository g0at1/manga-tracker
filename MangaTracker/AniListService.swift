import Foundation

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
}
