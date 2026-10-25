import Foundation

/// Reads what people type into a money or percent field: "55000", "55 000", "55 000 ₽", "$1,234.50", "12,5", "1.234,56".
public enum Amount {
    public static func parse(_ text: String) -> Decimal? {
        // Keep digits and separators; spaces, currency signs and letters go.
        let kept = text.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" }
        guard kept.contains(where: \.isNumber) else { return nil }
        var digits = kept.replacingOccurrences(of: "-", with: "")
        // The last separator followed by 1–2 digits is the decimal point; any other separator groups thousands.
        if let last = digits.lastIndex(where: { $0 == "," || $0 == "." }) {
            let tail = digits[digits.index(after: last)...]
            if (1...2).contains(tail.count) {
                digits = digits[..<last].filter(\.isNumber) + "." + tail
            } else {
                digits = digits.filter(\.isNumber)
            }
        }
        guard let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return kept.hasPrefix("-") ? -value : value
    }
}
