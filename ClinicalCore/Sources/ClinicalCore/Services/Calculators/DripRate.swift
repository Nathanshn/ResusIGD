import Foundation

/// Gravity drip conversions. Indonesian practice: makro = 20 tetes/mL, mikro = 60 tetes/mL.
public enum DripSet: Double, Codable, Sendable, CaseIterable {
    case macro = 20
    case micro = 60

    public var dropsPerML: Double { rawValue }

    public var label: String {
        switch self {
        case .macro: "Infus Makro (20 tetes/mL)"
        case .micro: "Infus Mikro (60 tetes/mL)"
        }
    }
}

public enum DripRate {
    /// mL/jam → tetes/menit.
    public static func dropsPerMinute(mLPerHour: Double, set: DripSet) -> Double {
        guard mLPerHour.isFinite, mLPerHour > 0 else { return 0 }
        return mLPerHour * set.dropsPerML / 60
    }

    /// tetes/menit → mL/jam.
    public static func mLPerHour(dropsPerMinute: Double, set: DripSet) -> Double {
        guard dropsPerMinute.isFinite, dropsPerMinute > 0 else { return 0 }
        return dropsPerMinute * 60 / set.dropsPerML
    }

    /// Volume (mL) over duration (hours) → mL/jam.
    public static func mLPerHour(volumeML: Double, overHours hours: Double) -> Double {
        guard volumeML > 0, hours > 0 else { return 0 }
        return volumeML / hours
    }
}

/// A rate expressed simultaneously as pump rate and gravity drips.
public struct RateTriple: Sendable, Hashable {
    public let mLPerHour: Double
    public let macroDropsPerMinute: Double
    public let microDropsPerMinute: Double

    public init(mLPerHour: Double) {
        let safe = (mLPerHour.isFinite && mLPerHour > 0) ? mLPerHour : 0
        self.mLPerHour = safe
        self.macroDropsPerMinute = DripRate.dropsPerMinute(mLPerHour: safe, set: .macro)
        self.microDropsPerMinute = DripRate.dropsPerMinute(mLPerHour: safe, set: .micro)
    }
}
