import Foundation

public enum WeightEstimationMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case apls
    case luscombeOwens
    case lengthZone
    case traubJohnson

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .apls: "APLS (usia)"
        case .luscombeOwens: "Luscombe-Owens (usia)"
        case .lengthZone: "Zona panjang badan (gaya Broselow)"
        case .traubJohnson: "Traub-Johnson (panjang badan)"
        }
    }

    public var formula: String {
        switch self {
        case .apls: "0–12 bln: (0,5 × bln) + 4 · 1–5 thn: (2 × thn) + 8 · 6–12 thn: (3 × thn) + 7"
        case .luscombeOwens: "(3 × thn) + 7, valid 1–10 thn"
        case .lengthZone: "Zona warna berdasarkan panjang badan (cm), BB = nilai tengah zona"
        case .traubJohnson: "BB = 2,05 × e^(0,02 × PB cm), valid PB 74–146 cm"
        }
    }
}

/// Length-based colour zone (Broselow-style). Boundaries are published approximations, not the proprietary tape.
public struct LengthZone: Sendable, Hashable {
    public let colorName: String
    public let colorKey: String
    public let minLengthCm: Double
    /// Exclusive upper bound.
    public let maxLengthCm: Double
    public let minWeightKg: Double
    public let maxWeightKg: Double

    public var midWeightKg: Double { (minWeightKg + maxWeightKg) / 2 }
    public var weightRangeLabel: String {
        "\(ClinicalFormat.number(minWeightKg))–\(ClinicalFormat.number(maxWeightKg)) kg"
    }
}

public struct WeightEstimate: Sendable, Hashable {
    public let method: WeightEstimationMethod
    public let weightKg: Double
    /// True when the input lies outside the population the formula was validated on.
    public let outsideValidatedRange: Bool
    public let zone: LengthZone?
    public let note: String
}

/// Weight estimation for the unweighed crash patient (“BB Tidak Diketahui”).
public enum PediatricWeightEstimator {
    public static let lengthZones: [LengthZone] = [
        LengthZone(colorName: "Abu-abu", colorKey: "grey", minLengthCm: 46, maxLengthCm: 59.5, minWeightKg: 3, maxWeightKg: 5),
        LengthZone(colorName: "Merah muda", colorKey: "pink", minLengthCm: 59.5, maxLengthCm: 67, minWeightKg: 6, maxWeightKg: 7),
        LengthZone(colorName: "Merah", colorKey: "red", minLengthCm: 67, maxLengthCm: 75, minWeightKg: 8, maxWeightKg: 9),
        LengthZone(colorName: "Ungu", colorKey: "purple", minLengthCm: 75, maxLengthCm: 85, minWeightKg: 10, maxWeightKg: 11),
        LengthZone(colorName: "Kuning", colorKey: "yellow", minLengthCm: 85, maxLengthCm: 98, minWeightKg: 12, maxWeightKg: 14),
        LengthZone(colorName: "Putih", colorKey: "white", minLengthCm: 98, maxLengthCm: 110, minWeightKg: 15, maxWeightKg: 18),
        LengthZone(colorName: "Biru", colorKey: "blue", minLengthCm: 110, maxLengthCm: 122, minWeightKg: 19, maxWeightKg: 23),
        LengthZone(colorName: "Oranye", colorKey: "orange", minLengthCm: 122, maxLengthCm: 137, minWeightKg: 24, maxWeightKg: 29),
        LengthZone(colorName: "Hijau", colorKey: "green", minLengthCm: 137, maxLengthCm: 150, minWeightKg: 30, maxWeightKg: 36)
    ]

    /// APLS (2011 update) age-based formula. `ageMonths` is total age in months.
    public static func apls(ageMonths: Double) -> WeightEstimate? {
        guard ageMonths >= 0, ageMonths.isFinite else { return nil }
        let years = ageMonths / 12
        let weight: Double
        if ageMonths < 12 {
            weight = 0.5 * ageMonths + 4
        } else if years < 6 {
            weight = 2 * years.rounded(.down) + 8
        } else {
            weight = 3 * years.rounded(.down) + 7
        }
        let outside = years >= 13
        return WeightEstimate(
            method: .apls, weightKg: weight, outsideValidatedRange: outside, zone: nil,
            note: outside ? "Formula APLS divalidasi untuk usia 0–12 tahun." : "Estimasi APLS berdasarkan usia."
        )
    }

    /// Luscombe-Owens: 3 × age (years) + 7, validated for 1–10 years.
    public static func luscombeOwens(ageMonths: Double) -> WeightEstimate? {
        guard ageMonths >= 0, ageMonths.isFinite else { return nil }
        let years = (ageMonths / 12).rounded(.down)
        let weight = 3 * years + 7
        let outside = ageMonths < 12 || years > 10
        return WeightEstimate(
            method: .luscombeOwens, weightKg: weight, outsideValidatedRange: outside, zone: nil,
            note: outside ? "Luscombe-Owens divalidasi untuk usia 1–10 tahun." : "Estimasi Luscombe-Owens berdasarkan usia."
        )
    }

    public static func zone(forLengthCm length: Double) -> LengthZone? {
        lengthZones.first { length >= $0.minLengthCm && length < $0.maxLengthCm }
    }

    /// Length-zone (Broselow-style) estimate: mid-point weight of the matching colour zone.
    public static func lengthZone(lengthCm: Double) -> WeightEstimate? {
        guard lengthCm > 0, lengthCm.isFinite else { return nil }
        if let zone = zone(forLengthCm: lengthCm) {
            return WeightEstimate(
                method: .lengthZone, weightKg: zone.midWeightKg, outsideValidatedRange: false, zone: zone,
                note: "Zona \(zone.colorName) (\(zone.weightRangeLabel)). Gunakan pita resmi bila tersedia."
            )
        }
        guard let traub = traubJohnson(lengthCm: lengthCm) else { return nil }
        return WeightEstimate(
            method: .lengthZone, weightKg: traub.weightKg, outsideValidatedRange: true, zone: nil,
            note: "Panjang badan di luar zona (46–150 cm); memakai Traub-Johnson. Timbang pasien sesegera mungkin."
        )
    }

    /// Traub-Johnson length-based exponential formula.
    public static func traubJohnson(lengthCm: Double) -> WeightEstimate? {
        guard lengthCm > 0, lengthCm.isFinite else { return nil }
        let weight = 2.05 * exp(0.02 * lengthCm)
        let outside = lengthCm < 74 || lengthCm > 146
        return WeightEstimate(
            method: .traubJohnson, weightKg: weight, outsideValidatedRange: outside, zone: nil,
            note: outside ? "Traub-Johnson divalidasi untuk PB 74–146 cm." : "Estimasi Traub-Johnson berdasarkan panjang badan."
        )
    }

    /// Best available estimate: length (more accurate) when given, otherwise age.
    public static func bestEstimate(lengthCm: Double?, ageMonths: Double?) -> WeightEstimate? {
        if let lengthCm, lengthCm > 0, let byLength = lengthZone(lengthCm: lengthCm) { return byLength }
        if let ageMonths, ageMonths >= 0 { return apls(ageMonths: ageMonths) }
        return nil
    }

    /// Inverse of APLS used to derive an "equivalent age" when only weight is known (for equipment sizing).
    public static func equivalentAgeMonths(forWeightKg weight: Double) -> Double {
        guard weight > 0 else { return 0 }
        if weight < 10 {
            return min(max((weight - 4) / 0.5, 0), 12)
        } else if weight <= 18 {
            return max(12, (weight - 8) / 2 * 12)
        } else if weight < 25 {
            return 5 * 12 + (weight - 18) / 7 * 12
        } else {
            return min((weight - 7) / 3 * 12, 16 * 12)
        }
    }
}
