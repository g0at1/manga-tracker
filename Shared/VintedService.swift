import Foundation

/// Second-hand listings from Vinted, for checking what a series or volume
/// goes for. Vinted has no public API and removed the JSON catalog endpoint
/// its web app used, so this reads the search page itself: the listings are
/// in the Next.js payload the server renders into it (the
/// `self.__next_f.push([1,"…"])` script chunks), as the same objects the
/// page's item grid is built from.
enum VintedService {
    private static let baseURL = URL(string: "https://www.vinted.pl")!

    /// Vinted answers bot-looking clients with a DataDome challenge; a
    /// browser user agent gets the plain page.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"

    enum ServiceError: LocalizedError {
        /// A challenge page or an error status instead of results.
        case blocked(status: Int)
        /// The page loaded but the listings weren't where they used to be —
        /// Vinted changed its markup.
        case unexpectedPage

        var errorDescription: String? {
            switch self {
            case let .blocked(status): L("Vinted odrzucił zapytanie (HTTP %lld). Spróbuj za chwilę.", status)
            case .unexpectedPage: L("Nie udało się odczytać wyników z Vinted.")
            }
        }
    }

    /// Vinted's `order` value for each sort.
    private static func orderValue(_ order: MarketSortOrder) -> String {
        switch order {
        case .relevance: "relevance"
        case .priceLowToHigh: "price_low_to_high"
        case .newestFirst: "newest_first"
        }
    }

    /// Vinted's catalog id for each category.
    private static func catalogID(_ category: MarketCategory) -> String? {
        switch category {
        case .comics: "5425"
        case .books: "2312"
        case .all: nil
        }
    }

    /// First page only: Vinted serves 96 per page, more than enough to
    /// price a series.
    static func search(
        _ query: String,
        order: MarketSortOrder = .relevance,
        category: MarketCategory = .all
    ) async throws -> [MarketListing] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(url: baseURL.appending(path: "catalog"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "search_text", value: trimmed),
            URLQueryItem(name: "order", value: orderValue(order)),
        ]
        if let catalog = catalogID(category) {
            components.queryItems?.append(URLQueryItem(name: "catalog[]", value: catalog))
        }

        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("pl-PL,pl;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ServiceError.blocked(status: status) }

        return try parseCatalogPage(data)
    }

    // MARK: - Parsing

    /// Pulls the listings out of a catalog page. Internal for the tests.
    static func parseCatalogPage(_ html: Data) throws -> [MarketListing] {
        let payload = flightPayload(in: [UInt8](html))
        guard let arrayData = jsonArray(after: Array(#""items":{"items":"#.utf8), in: payload) else {
            throw ServiceError.unexpectedPage
        }
        let entries = try JSONDecoder().decode([CatalogEntry].self, from: arrayData)
        return entries.compactMap { $0.productItem.listing(relativeTo: baseURL) }
    }

    /// The page's Next.js payload, which arrives as JSON string literals
    /// split over several `<script>` tags; decoded and joined back up.
    private static func flightPayload(in html: [UInt8]) -> [UInt8] {
        let marker = Array(#"self.__next_f.push([1,""#.utf8)
        var payload: [UInt8] = []
        var index = 0

        while let start = firstIndex(of: marker, in: html, from: index) {
            // The literal starts at the marker's closing quote.
            let literalStart = start + marker.count - 1
            var cursor = literalStart + 1
            while cursor < html.count, html[cursor] != UInt8(ascii: "\"") {
                cursor += html[cursor] == UInt8(ascii: "\\") ? 2 : 1
            }
            guard cursor < html.count else { break }

            let literal = Data(html[literalStart ... cursor])
            if let chunk = try? JSONDecoder().decode(String.self, from: literal) {
                payload.append(contentsOf: chunk.utf8)
            }
            index = cursor + 1
        }
        return payload
    }

    /// The JSON array that directly follows `key`, cut out by matching
    /// brackets (outside strings) so the rest of the payload, which isn't
    /// JSON, never reaches the decoder.
    private static func jsonArray(after key: [UInt8], in bytes: [UInt8]) -> Data? {
        guard let keyStart = firstIndex(of: key, in: bytes, from: 0) else { return nil }
        let start = keyStart + key.count
        guard start < bytes.count, bytes[start] == UInt8(ascii: "[") else { return nil }

        var depth = 0
        var inString = false
        var cursor = start
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if inString {
                if byte == UInt8(ascii: "\\") {
                    cursor += 1
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
            } else {
                switch byte {
                case UInt8(ascii: "\""): inString = true
                case UInt8(ascii: "["), UInt8(ascii: "{"): depth += 1
                case UInt8(ascii: "]"), UInt8(ascii: "}"):
                    depth -= 1
                    if depth == 0 { return Data(bytes[start ... cursor]) }
                default: break
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func firstIndex(of needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int? {
        guard let first = needle.first, haystack.count >= needle.count else { return nil }
        var index = start
        let last = haystack.count - needle.count
        while index <= last {
            if haystack[index] == first, haystack[index ..< index + needle.count].elementsEqual(needle) {
                return index
            }
            index += 1
        }
        return nil
    }

    // MARK: - Payload shapes

    private struct CatalogEntry: Decodable {
        let productItem: ProductItem
    }

    private struct ProductItem: Decodable {
        struct Money: Decodable {
            let amount: String
            let currencyCode: String
        }

        struct ItemBox: Decodable {
            /// The condition, as Vinted words it ("Bardzo dobry").
            let secondLine: String?
        }

        let id: Int
        let title: String
        let url: String
        let favouriteCount: Int?
        let price: Money
        let priceWithDiscount: Money?
        let totalItemPrice: Money?
        let thumbnailUrl: String?
        let itemBox: ItemBox?

        func listing(relativeTo base: URL) -> MarketListing? {
            let shownPrice = priceWithDiscount ?? price
            guard let amount = Double(shownPrice.amount),
                  let itemURL = URL(string: url, relativeTo: base)?.absoluteURL
            else { return nil }

            return MarketListing(
                id: "vinted-\(id)",
                source: .vinted,
                title: title,
                condition: itemBox?.secondLine,
                price: amount,
                totalPrice: totalItemPrice.flatMap { Double($0.amount) },
                currencyCode: shownPrice.currencyCode,
                thumbnailURL: thumbnailUrl.flatMap(URL.init(string:)),
                url: itemURL,
                favouriteCount: favouriteCount ?? 0
            )
        }
    }
}
