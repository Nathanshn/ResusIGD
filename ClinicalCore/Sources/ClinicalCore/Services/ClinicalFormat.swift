import Foundation

/// Locale-independent Indonesian number formatting (thousands ".", decimal ",") and lenient parsing.
/// Deliberately does not use `NumberFormatter` so output is identical on every platform and in tests.
public enum ClinicalFormat {
    /// Formats `value` rounded half-away-from-zero to `maxDecimals`, trimming trailing zeros down to `minDecimals`.
    public static func number(_ value: Double, maxDecimals: Int = 2, minDecimals: Int = 0) -> String {
        guard value.isFinite else { return "–" }
        let decimals = min(max(0, maxDecimals), 6)
        var factor: Int64 = 1
        for _ in 0..<decimals { factor *= 10 }
        let scaledDouble = (abs(value) * Double(factor)).rounded(.toNearestOrAwayFromZero)
        guard scaledDouble < 9e15 else { return "–" }
        let scaled = Int64(scaledDouble)
        let integerPart = scaled / factor
        let fractionPart = scaled % factor

        var fraction = ""
        if decimals > 0 {
            let digits = String(fractionPart)
            fraction = String(repeating: "0", count: max(0, decimals - digits.count)) + digits
            while fraction.count > minDecimals, fraction.hasSuffix("0") {
                fraction.removeLast()
            }
        }

        let grouped = groupThousands(String(integerPart))
        let isZero = scaled == 0
        let sign = (value < 0 && !isZero) ? "-" : ""
        return fraction.isEmpty ? sign + grouped : sign + grouped + "," + fraction
    }

    /// Dose in mg/mcg with precision adapted to magnitude.
    public static func dose(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude < 0.1 { return number(value, maxDecimals: 3) }
        if magnitude < 10 { return number(value, maxDecimals: 2) }
        if magnitude < 100 { return number(value, maxDecimals: 1) }
        return number(value, maxDecimals: 0)
    }

    /// Volume in mL with precision adapted to magnitude (≥ 0,01 mL for small volumes).
    public static func volume(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude < 1 { return number(value, maxDecimals: 2) }
        if magnitude < 100 { return number(value, maxDecimals: 1) }
        return number(value, maxDecimals: 0)
    }

    /// Pump rate in mL/jam (one decimal place — typical syringe-pump resolution).
    public static func rate(_ value: Double) -> String {
        number(value, maxDecimals: 1, minDecimals: 1)
    }

    /// Drops per minute. Shown as whole drops; values < 10 keep one decimal so small rates are not hidden.
    public static func drops(_ value: Double) -> String {
        abs(value) < 10 ? number(value, maxDecimals: 1) : number(value, maxDecimals: 0)
    }

    /// Parses user input accepting either "," or "." as decimal separator. Returns nil for empty / invalid text.
    public static func parse(_ text: String) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        if cleaned.contains(",") && cleaned.contains(".") {
            // "1.234,5" → thousands "." + decimal ","
            cleaned = cleaned.replacingOccurrences(of: ".", with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    private static func groupThousands(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        var result = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { result.append(".") }
            result.append(character)
        }
        return String(result.reversed())
    }
}

extension Double {
    /// Rounds to the nearest multiple of `step` (step > 0).
    func rounded(toStep step: Double) -> Double {
        guard step > 0 else { return self }
        return (self / step).rounded(.toNearestOrAwayFromZero) * step
    }

    /// Rounds down to the nearest multiple of `step` (step > 0), tolerant of floating point noise.
    func floored(toStep step: Double) -> Double {
        guard step > 0 else { return self }
        return (self / step + 1e-9).rounded(.down) * step
    }

    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
