import Foundation

/// A book as the Polish National Library (Biblioteka Narodowa) catalogues
/// it, reduced to what places a manga volume in a series.
struct CataloguedBook: Equatable {
    var isbn: String
    /// The series as the Polish edition names it: "One piece",
    /// "Frieren: u kresu drogi".
    var seriesTitle: String
    var volumeNumber: Int?
    /// The volume's own title when it has one ("Romance Dawn - przygoda na
    /// horyzoncie"); nil when the volume is just "Series. 3".
    var volumeTitle: String?
    /// The title the edition was translated from, when the record gives
    /// it — often what AniList knows the series by.
    var originalTitle: String?
    /// "Eiichiro Oda", from the record's "Oda, Eiichiro".
    var author: String?
    var publisher: String?
    /// Other ISBNs on the record, chiefly the whole series' ("ISBN(całość)").
    var otherISBNs: [String]
}

/// Looks ISBNs up in the National Library's open catalogue
/// (data.bn.org.pl). Every book published in Poland is deposited there, so
/// Polish manga editions are covered from Waneko to JPF and Studio JG; the
/// catalogue carries no prices. Free, no key.
enum NationalLibraryService {
    static func lookup(isbn: String) async throws -> CataloguedBook? {
        var components = URLComponents(string: "https://data.bn.org.pl/api/institutions/bibs.json")!
        components.queryItems = [
            URLQueryItem(name: "isbnIssn", value: isbn),
            URLQueryItem(name: "limit", value: "5"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try parse(data, isbn: isbn)
    }

    // MARK: - Parsing

    /// The record for `isbn` in a catalogue response, or nil when there's
    /// none. Only records listing the ISBN count; among those, one that
    /// numbers the volume wins over one that doesn't (a whole-series entry).
    static func parse(_ data: Data, isbn: String) throws -> CataloguedBook? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let records = response.bibs.filter { $0.deleted != true }
        let books = records.compactMap { book(from: $0, isbn: isbn) }
        return books.first { $0.volumeNumber != nil } ?? books.first
    }

    private static func book(from record: Response.Record, isbn: String) -> CataloguedBook? {
        let fields = record.marc?.fields ?? []
        func all(_ tag: String) -> [Field] {
            fields.compactMap { $0[tag] }
        }

        var recordISBNs: [String] = []
        for field in all("020") {
            for value in field.values("a") {
                if let normalized = ISBN.normalized(value), !recordISBNs.contains(normalized) {
                    recordISBNs.append(normalized)
                }
            }
        }
        if recordISBNs.isEmpty {
            recordISBNs = (record.isbnIssn ?? "").split(separator: " ").compactMap { ISBN.normalized(String($0)) }
        }
        guard recordISBNs.contains(isbn) else { return nil }

        guard let titleField = all("245").first else { return nil }
        let mainTitle = cleaned(titleField.value("a") ?? "")
        let subtitle = titleField.value("b").map { cleaned($0) }
        let fullTitle = [mainTitle, subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ": ")

        var series: String?
        var number: Int?

        // "Series. 3 /": the volume is numbered in its own title.
        if let part = titleField.value("n"), let parsed = firstNumber(in: part) {
            series = fullTitle
            number = parsed
        }
        // "Volume title" with the series as an added entry ("One piece",
        // "t. 1"): author/series (800) first, then the series statement.
        if number == nil {
            let candidates = all("800").map { ($0.value("t"), $0.value("v")) }
                + all("490").map { ($0.value("a"), $0.value("v")) }
                + all("830").map { ($0.value("a"), $0.value("v")) }
            for (title, volume) in candidates {
                guard let title, let volume, let parsed = firstNumber(in: volume) else { continue }
                series = cleaned(seriesName(title))
                number = parsed
                break
            }
        }

        let volumeTitle = (series != nil && series != fullTitle) ? fullTitle : nil

        return CataloguedBook(
            isbn: isbn,
            seriesTitle: series ?? fullTitle,
            volumeNumber: number,
            volumeTitle: volumeTitle?.isEmpty == true ? nil : volumeTitle,
            originalTitle: originalTitle(fields: fields),
            author: (all("100").first?.value("a")).map { invertedName($0) },
            publisher: (all("264").first ?? all("260").first)?.value("b").map { cleaned($0) },
            otherISBNs: recordISBNs.filter { $0 != isbn }
        )
    }

    /// From the "original title" variant (246) or the note
    /// "Tyt. oryg.: One piece, 1997." (500).
    private static func originalTitle(fields: [[String: Field]]) -> String? {
        for field in fields.compactMap({ $0["246"] }) {
            let label = field.value("i")?.lowercased() ?? ""
            if label.contains("oryg"), let title = field.value("a") {
                return cleaned(title)
            }
        }
        for field in fields.compactMap({ $0["500"] }) {
            guard let note = field.value("a"),
                  let range = note.range(of: "Tyt. oryg.:", options: .caseInsensitive)
            else { continue }
            let rest = note[range.upperBound...]
            let title = rest.split(whereSeparator: { $0 == "," || $0 == "." }).first.map(String.init) ?? ""
            let trimmed = cleaned(title)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    /// "One piece / Eiichiro Oda ;" → "One piece".
    private static func seriesName(_ statement: String) -> String {
        String(statement.split(separator: "/", maxSplits: 1).first ?? Substring(statement))
    }

    /// "Oda, Eiichiro" → "Eiichiro Oda".
    private static func invertedName(_ value: String) -> String {
        let parts = cleaned(value).split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        return parts.count == 2 ? "\(parts[1]) \(parts[0])" : cleaned(value)
    }

    /// The first whole number: "t. 1" → 1, "11 /" → 11, "Vol. 4," → 4.
    static func firstNumber(in text: String) -> Int? {
        guard let range = text.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(text[range])
    }

    /// Strips the catalogue's punctuation: trailing " /", " :", ";", ",",
    /// "." and surrounding brackets.
    static func cleaned(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailing: Set<Character> = ["/", ":", ";", ",", ".", "=", " "]
        while let last = result.last, trailing.contains(last) {
            result.removeLast()
        }
        if result.hasPrefix("["), result.hasSuffix("]") {
            result = String(result.dropFirst().dropLast())
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Response

    private struct Response: Decodable {
        let bibs: [Record]

        struct Record: Decodable {
            let deleted: Bool?
            let isbnIssn: String?
            let marc: Marc?
        }

        struct Marc: Decodable {
            let fields: [[String: Field]]
        }
    }

    /// A MARC field: control fields ("001") are plain strings, data fields
    /// carry indicators and a list of one-letter subfields.
    fileprivate enum Field: Decodable {
        case control(String)
        case data([[String: String]])

        private struct DataField: Decodable {
            let subfields: [[String: String]]
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .control(text)
            } else {
                self = try .data(container.decode(DataField.self).subfields)
            }
        }

        func values(_ code: String) -> [String] {
            guard case let .data(subfields) = self else { return [] }
            return subfields.compactMap { $0[code] }
        }

        func value(_ code: String) -> String? {
            values(code).first
        }
    }
}
