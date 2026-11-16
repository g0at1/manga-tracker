@testable import MangaTrackerIOS
import XCTest

/// Reading listings out of Vinted's catalog page and OLX's offers API, and
/// the matching and price summary over them. No network.
///
/// Vinted's payload is split over several escaped script chunks, and the
/// item array has to be cut out of text that isn't JSON.
final class MarketplaceParsingTests: XCTestCase {
    /// A catalog page cut down to what the parser looks at, with the item
    /// array broken across two chunks the way Next.js streams it.
    private let page = #"""
    <html><body>
    <script>self.__next_f.push([1,"3:[\"$\",\"div\",null,{\"items\":{\"items\":[{\"id\":1,\"productItem\":{\"id\":1,\"title\":\"Berserk tom 1 \\\"nowy\\\"\",\"url\":\"/items/1-berserk\",\"favouriteCount\":9,\"priceWithDiscount\":null,\"price\":{\"amount\":\"40.00\",\"currencyCode\":\"PLN\"},"])</script>
    <script>self.__next_f.push([1,"\"totalItemPrice\":{\"amount\":\"44.90\",\"currencyCode\":\"PLN\"},\"thumbnailUrl\":\"https://images1.vinted.net/t/a.webp\",\"itemBox\":{\"secondLine\":\"Nowy bez metki\"}}},{\"id\":2,\"productItem\":{\"id\":2,\"title\":\"Berserk tomy 1-5 [komplet]\",\"url\":\"/items/2-berserk\",\"price\":{\"amount\":\"150.00\",\"currencyCode\":\"PLN\"},\"priceWithDiscount\":{\"amount\":\"120.00\",\"currencyCode\":\"PLN\"}}}],\"pagination\":{}}}]"])</script>
    </body></html>
    """#

    func testListingsAreReadAcrossChunks() throws {
        let listings = try VintedService.parseCatalogPage(Data(page.utf8))

        XCTAssertEqual(listings.count, 2)

        let first = listings[0]
        XCTAssertEqual(first.title, #"Berserk tom 1 "nowy""#)
        XCTAssertEqual(first.price, 40)
        XCTAssertEqual(first.totalPrice, 44.9)
        XCTAssertEqual(first.condition, "Nowy bez metki")
        XCTAssertEqual(first.favouriteCount, 9)
        XCTAssertEqual(first.url.absoluteString, "https://www.vinted.pl/items/1-berserk")

        // Brackets inside a title don't end the array early, and a
        // discount is what the listing costs.
        XCTAssertEqual(listings[1].title, "Berserk tomy 1-5 [komplet]")
        XCTAssertEqual(listings[1].price, 120)
        XCTAssertNil(listings[1].totalPrice)
    }

    func testPageWithoutListingsIsAnError() {
        XCTAssertThrowsError(try VintedService.parseCatalogPage(Data("<html>captcha</html>".utf8)))
    }

    /// Trimmed from a real response: one promoted, negotiable listing, one
    /// fixed price without photos, and a swap with nothing to compare.
    private let offers = #"""
    {"data":[
      {"id":11,"url":"https://www.olx.pl/d/oferta/berserk-1-3.html","title":"Manga Berserk tomy 1-3",
       "params":[{"key":"covertype","value":{"key":"hard","label":"Twarda"}},
                 {"key":"price","value":{"value":450,"type":"arranged","currency":"PLN","label":"450 zł"}},
                 {"key":"state","value":{"key":"used","label":"Używane"}}],
       "photos":[{"link":"https://ireland.apollo.olxcdn.com:443/v1/files/abc-PL/image;s={width}x{height}"}],
       "location":{"city":{"id":1,"name":"Kraków"}}},
      {"id":12,"url":"https://www.olx.pl/d/oferta/berserk-1.html","title":"Berserk tom 1",
       "params":[{"key":"price","value":{"value":30.99,"type":"price","currency":"PLN"}}],
       "photos":[],"location":{}},
      {"id":13,"url":"https://www.olx.pl/d/oferta/zamienie.html","title":"Zamienię Berserk",
       "params":[{"key":"price","value":{"type":"exchange"}}]}
    ],"metadata":{}}
    """#

    func testOLXOffersAreRead() throws {
        let listings = try OLXService.parseOffers(Data(offers.utf8))

        XCTAssertEqual(listings.map(\.id), ["olx-11", "olx-12"])

        let first = listings[0]
        XCTAssertEqual(first.price, 450)
        XCTAssertTrue(first.isNegotiable)
        XCTAssertEqual(first.condition, "Używane")
        XCTAssertEqual(first.location, "Kraków")
        XCTAssertEqual(first.thumbnailURL?.absoluteString, "https://ireland.apollo.olxcdn.com:443/v1/files/abc-PL/image;s=400x400")

        XCTAssertEqual(listings[1].price, 30.99)
        XCTAssertFalse(listings[1].isNegotiable)
        XCTAssertNil(listings[1].thumbnailURL)
        XCTAssertNil(listings[1].location)
    }

    func testMatchingIgnoresCaseAccentsAndFiller() {
        func listing(_ title: String) -> MarketListing {
            MarketListing(
                id: "0", source: .vinted, title: title, condition: nil, price: 0,
                currencyCode: "PLN", thumbnailURL: nil, url: URL(string: "https://www.vinted.pl")!
            )
        }

        XCTAssertTrue(listing("ONE PIECE 1 manga").matches("One Piece tom 1"))
        XCTAssertTrue(listing("Manga Berserk Tom1 Deluxe Edition").matches("Berserk tom 1"))
        XCTAssertFalse(listing("Manga Ao No Exorcist tomy 1-5").matches("ao no exorcist 3"))
        XCTAssertTrue(listing("Pokémon Adventures vol. 2").matches("pokemon adventures tom 2"))
        XCTAssertFalse(listing("Bakuman tom 1").matches("One Piece tom 1"))
        XCTAssertFalse(listing("One Piece tom 10").matches("One Piece tom 1"))
    }

    func testPriceSummary() throws {
        let listings = [40.0, 10, 30, 20].enumerated().map { index, price in
            MarketListing(
                id: "\(index)", source: .vinted, title: "", condition: nil, price: price,
                currencyCode: "PLN", thumbnailURL: nil, url: URL(string: "https://www.vinted.pl")!
            )
        }
        let summary = try XCTUnwrap(MarketPriceSummary(listings))
        XCTAssertEqual(summary.lowest, 10)
        XCTAssertEqual(summary.median, 25)
        XCTAssertEqual(summary.highest, 40)
        XCTAssertNil(MarketPriceSummary([]))
    }
}
