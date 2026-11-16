import Foundation

/// Second-hand marketplaces searched for what a series or volume goes for.
enum Marketplace: String, CaseIterable, Identifiable {
    case vinted
    case olx

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .vinted: "Vinted"
        case .olx: "OLX"
        }
    }

    func search(_ query: String, order: MarketSortOrder, category: MarketCategory) async throws -> [MarketListing] {
        switch self {
        case .vinted: try await VintedService.search(query, order: order, category: category)
        case .olx: try await OLXService.search(query, order: order, category: category)
        }
    }
}

/// How far to narrow a search by the sites' own categories. Without one a
/// title also finds hoodies, posters and figures.
enum MarketCategory: String, CaseIterable, Identifiable {
    /// Vinted's "Komiksy, manga i powieści graficzne"; OLX's "Komiksy",
    /// which holds "Manga" but also "Pozostałe", where many sellers put it.
    case comics
    /// All books, for listings filed under literature or the like.
    case books
    case all

    var id: String {
        rawValue
    }
}

/// The orders both sites' sort menus offer.
enum MarketSortOrder: String, CaseIterable, Identifiable {
    case relevance
    case priceLowToHigh
    case newestFirst

    var id: String {
        rawValue
    }
}

/// One listing from a marketplace search.
struct MarketListing: Identifiable, Hashable {
    /// Prefixed with the site, so listings from both can share a list.
    let id: String
    let source: Marketplace
    let title: String
    let condition: String?
    /// What the seller asks.
    let price: Double
    /// With Vinted's buyer-protection fee, which is what checkout charges.
    var totalPrice: Double? = nil
    let currencyCode: String
    let thumbnailURL: URL?
    let url: URL
    var favouriteCount = 0
    /// The seller's town (OLX).
    var location: String? = nil
    /// Price open to haggling (OLX's "do negocjacji").
    var isNegotiable = false

    /// Words that say nothing about which series it is, and that sellers
    /// use or leave out at random.
    private static let fillerWords: Set<String> = ["tom", "tomy", "tomu", "vol", "volume", "manga", "mangi", "nr"]

    /// Both sites search loosely, and also return listings they merely find
    /// related ("Bakuman tom 1" for "One Piece tom 1"). True when the title
    /// has every word of the query, ignoring case, accents and filler.
    func matches(_ query: String) -> Bool {
        let titleWords = Set(Self.words(in: title))
        return Self.words(in: query)
            .filter { !Self.fillerWords.contains($0) }
            .allSatisfy(titleWords.contains)
    }

    /// Letters and digits run together ("Tom1") count as separate words.
    private static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: #"(?<=\p{L})(?=\d)|(?<=\d)(?=\p{L})"#, with: " ", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

/// Price spread over a set of listings, on the seller's prices.
struct MarketPriceSummary {
    let count: Int
    let lowest: Double
    let median: Double
    let highest: Double

    init?(_ listings: [MarketListing]) {
        let prices = listings.map(\.price).sorted()
        guard let lowest = prices.first, let highest = prices.last else { return nil }
        let middle = prices.count / 2
        count = prices.count
        self.lowest = lowest
        self.highest = highest
        median = prices.count.isMultiple(of: 2) ? (prices[middle - 1] + prices[middle]) / 2 : prices[middle]
    }
}
