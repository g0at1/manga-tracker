import Foundation

enum DateFormatters {
    static let yyyyMMdd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension Date {
    func yyyyMMdd() -> String {
        DateFormatters.yyyyMMdd.string(from: self)
    }
}
