import Foundation

/// Second-hand listings from OLX. Its web app searches through a JSON API
/// that answers without a session, so this asks it directly. CloudFront in
/// front of it turns away curl and the like, but not URLSession.
enum OLXService {
    private static let apiBase = URL(string: "https://www.olx.pl/api/v1/offers/")!

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"

    /// The API's ceiling per request. Two pages make roughly what one
    /// Vinted page holds.
    private static let pageSize = 50
    private static let pageCount = 2

    enum ServiceError: LocalizedError {
        case blocked(status: Int)

        var errorDescription: String? {
            switch self {
            case let .blocked(status): L("OLX odrzucił zapytanie (HTTP %lld). Spróbuj za chwilę.", status)
            }
        }
    }

    /// OLX's `sort_by` value for each sort; relevance is its default.
    private static func sortValue(_ order: MarketSortOrder) -> String? {
        switch order {
        case .relevance: nil
        case .priceLowToHigh: "filter_float_price:asc"
        case .newestFirst: "created_at:desc"
        }
    }

    /// OLX's `category_id` for each category; a parent takes in its
    /// subcategories.
    private static func categoryID(_ category: MarketCategory) -> String? {
        switch category {
        case .comics: "1161"
        case .books: "453"
        case .all: nil
        }
    }

    static func search(
        _ query: String,
        order: MarketSortOrder = .relevance,
        category: MarketCategory = .all
    ) async throws -> [MarketListing] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let pages = try await withThrowingTaskGroup(of: (Int, [MarketListing]).self) { group in
            for page in 0 ..< pageCount {
                group.addTask {
                    try await (page, fetchPage(trimmed, order: order, category: category, offset: page * pageSize))
                }
            }
            return try await group.reduce(into: [Int: [MarketListing]]()) { $0[$1.0] = $1.1 }
        }

        // A promoted listing is pinned to the top of every page.
        var seen = Set<String>()
        return (0 ..< pageCount)
            .flatMap { pages[$0] ?? [] }
            .filter { seen.insert($0.id).inserted }
    }

    private static func fetchPage(
        _ query: String,
        order: MarketSortOrder,
        category: MarketCategory,
        offset: Int
    ) async throws -> [MarketListing] {
        var components = URLComponents(url: apiBase, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(pageSize)),
        ]
        if let sort = sortValue(order) {
            components.queryItems?.append(URLQueryItem(name: "sort_by", value: sort))
        }
        if let id = categoryID(category) {
            components.queryItems?.append(URLQueryItem(name: "category_id", value: id))
        }

        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("pl-PL,pl;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ServiceError.blocked(status: status) }

        return try parseOffers(data)
    }

    // MARK: - Parsing

    /// Internal for the tests.
    static func parseOffers(_ data: Data) throws -> [MarketListing] {
        try JSONDecoder().decode(OffersResponse.self, from: data).data.compactMap(\.listing)
    }

    private struct OffersResponse: Decodable {
        let data: [Offer]
    }

    private struct Offer: Decodable {
        /// One attribute of a listing. `value` differs by key: an object
        /// with a `label` for selects like the condition, the price fields
        /// for `price`.
        struct Param: Decodable {
            struct Value: Decodable {
                let label: String?
                let value: Double?
                let currency: String?
                /// "price", "arranged" (negotiable), "exchange" or "free".
                let type: String?
            }

            let key: String
            let value: Value?
        }

        struct Photo: Decodable {
            /// A template with `{width}x{height}` to fill in.
            let link: String
        }

        struct Location: Decodable {
            struct Named: Decodable {
                let name: String
            }

            let city: Named?
        }

        let id: Int
        let url: String
        let title: String
        let params: [Param]
        let photos: [Photo]?
        let location: Location?

        /// Nil for swaps and giveaways, which have no price to compare.
        var listing: MarketListing? {
            guard let price = params.first(where: { $0.key == "price" })?.value,
                  let amount = price.value, amount > 0,
                  let offerURL = URL(string: url)
            else { return nil }

            return MarketListing(
                id: "olx-\(id)",
                source: .olx,
                title: title,
                condition: params.first { $0.key == "state" }?.value?.label,
                price: amount,
                currencyCode: price.currency ?? "PLN",
                thumbnailURL: photos?.first.flatMap {
                    URL(string: $0.link.replacingOccurrences(of: "{width}x{height}", with: "400x400"))
                },
                url: offerURL,
                location: location?.city?.name,
                isNegotiable: price.type == "arranged"
            )
        }
    }
}
