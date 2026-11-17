import Foundation

/// ISBNs as printed and as barcodes carry them. Everything is reduced to
/// the 13 digits of an ISBN-13, the form the barcode on a book encodes and
/// the one stored on `Volume.isbn`.
enum ISBN {
    /// The ISBN-13 in `raw`, digits only, or nil when it isn't a valid one.
    /// Takes a barcode payload ("9788374712019"), a printed ISBN with
    /// hyphens or spaces ("978-83-7471-201-9"), or an ISBN-10 (converted,
    /// "83-7471-201-X" style check digit included). The check digit must
    /// be right, so a misread barcode or a typo is rejected.
    static func normalized(_ raw: String) -> String? {
        let characters = raw.uppercased().filter { $0.isNumber || $0 == "X" }
        let digits = String(characters)

        if digits.count == 13, digits.allSatisfy(\.isASCIIDigit) {
            guard digits.hasPrefix("978") || digits.hasPrefix("979") else { return nil }
            return checkDigit13(for: digits.prefix(12)) == digits.last ? digits : nil
        }

        if digits.count == 10 {
            let body = digits.prefix(9)
            guard body.allSatisfy(\.isASCIIDigit), checkDigit10(for: body) == digits.last else { return nil }
            let prefixed = "978" + body
            return prefixed + String(checkDigit13(for: Substring(prefixed)))
        }

        return nil
    }

    /// Every valid ISBN-13 in a block of text, in order, without repeats —
    /// for recognized text like "ISBN(tom 1):978-83-7471-201-9".
    static func all(in text: String) -> [String] {
        let pattern = #"(?:97[89][\s-]?)?(?:\d[\s-]?){9}[\dXx]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var found: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range, in: text),
                  let isbn = normalized(String(text[swiftRange])),
                  !found.contains(isbn)
            else { continue }
            found.append(isbn)
        }
        return found
    }

    /// "978-83-7471-201-9" from "9788374712019", for display. Splits as
    /// Polish ISBNs (978-83) usually are only when it can't be wrong:
    /// otherwise prefix and the rest.
    static func formatted(_ isbn: String) -> String {
        guard isbn.count == 13 else { return isbn }
        let digits = Array(isbn)
        return String(digits[0 ..< 3]) + "-" + String(digits[3 ..< 12]) + "-" + String(digits[12])
    }

    private static func checkDigit13(for body: Substring) -> Character {
        var sum = 0
        for (index, character) in body.enumerated() {
            let value = character.wholeNumberValue ?? 0
            sum += index.isMultiple(of: 2) ? value : value * 3
        }
        return Character(String((10 - sum % 10) % 10))
    }

    private static func checkDigit10(for body: Substring) -> Character {
        var sum = 0
        for (index, character) in body.enumerated() {
            sum += (character.wholeNumberValue ?? 0) * (10 - index)
        }
        let check = (11 - sum % 11) % 11
        return check == 10 ? "X" : Character(String(check))
    }
}

/// The cover price Polish publishers print next to the barcode,
/// "CENA: 25,20zł (w tym VAT 5%)", read out of recognized text.
enum PrintedPrice {
    /// The price in złoty, or nil when the text has none. Only an amount
    /// tied to "cena" or to a currency (zł, PLN) counts, so the VAT rate,
    /// an ISBN or a page count is never taken for a price.
    static func parse(_ text: String) -> Double? {
        let amount = #"(\d{1,4}(?:[.,]\d{1,2})?)"#
        let patterns = [
            #"(?i)cena[^\d]{0,12}"# + amount,
            amount + #"\s*(?i:zł|zl|pln)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let swiftRange = Range(match.range(at: 1), in: text)
            else { continue }
            let number = text[swiftRange].replacingOccurrences(of: ",", with: ".")
            if let value = Double(number), value > 0 {
                return value
            }
        }
        return nil
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
