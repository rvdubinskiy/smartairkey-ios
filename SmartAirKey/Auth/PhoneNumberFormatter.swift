import Foundation

/// Formats and validates Russian/CIS phone numbers (+7) for the sign-in field.
///
/// Kept free of any SDK/UIKit so the masking and validation are unit-testable.
/// Display mask: `+7 (XXX) XXX-XX-XX`; the API value is E.164 `+7XXXXXXXXXX`.
enum PhoneNumberFormatter {

    /// Up to 10 national digits, dropping a leading country code (7 or 8) and
    /// anything non-numeric — so pasting `+7…`, `8…` or a formatted string works.
    static func nationalDigits(_ raw: String) -> String {
        var digits = raw.filter(\.isNumber)
        if digits.first == "7" || digits.first == "8" {
            digits.removeFirst()
        }
        return String(digits.prefix(10))
    }

    /// Display string with the mask applied, always prefixed with `+7`.
    static func format(_ raw: String) -> String {
        let digits = Array(nationalDigits(raw))
        guard !digits.isEmpty else { return "+7" }

        var result = "+7 ("
        for (index, digit) in digits.enumerated() {
            switch index {
            case 3: result += ") "
            case 6: result += "-"
            case 8: result += "-"
            default: break
            }
            result.append(digit)
        }
        return result
    }

    /// E.164 value for the backend (`+7XXXXXXXXXX`), or nil if incomplete.
    static func e164(_ raw: String) -> String? {
        let digits = nationalDigits(raw)
        return digits.count == 10 ? "+7" + digits : nil
    }

    /// A complete, valid number has exactly 10 national digits.
    static func isValid(_ raw: String) -> Bool {
        nationalDigits(raw).count == 10
    }
}
