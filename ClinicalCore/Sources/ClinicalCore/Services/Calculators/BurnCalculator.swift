import Foundation

/// Body regions for the Rule of Nines selector.
public enum BurnRegion: String, Codable, Sendable, CaseIterable, Identifiable {
    case headNeck
    case anteriorTrunk
    case posteriorTrunk
    case rightArm
    case leftArm
    case rightLeg
    case leftLeg
    case perineum

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .headNeck: "Kepala & Leher"
        case .anteriorTrunk: "Badan Depan (dada + perut)"
        case .posteriorTrunk: "Badan Belakang (punggung + bokong)"
        case .rightArm: "Lengan Kanan"
        case .leftArm: "Lengan Kiri"
        case .rightLeg: "Tungkai Kanan"
        case .leftLeg: "Tungkai Kiri"
        case .perineum: "Perineum / Genitalia"
        }
    }
}

public enum RuleOfNines {
    /// Region %TBSA. Adults: classic Rule of Nines (total 100% incl. perineum 1%).
    /// Children: infant chart (head 18%, each leg 13,5%) adjusted per year above 1:
    /// head −1%, each leg +0,5% — reaching adult proportions at age 10. Total always 100%.
    public static func percentage(of region: BurnRegion, ageYears: Double?) -> Double {
        let years = ageYears ?? 18
        let yearsAboveOne = min(max(years.rounded(.down) - 1, 0), 9)
        switch region {
        case .headNeck: return 18 - yearsAboveOne
        case .anteriorTrunk, .posteriorTrunk: return 18
        case .rightArm, .leftArm: return 9
        case .rightLeg, .leftLeg: return 13.5 + 0.5 * yearsAboveOne
        case .perineum: return 1
        }
    }

    /// `fractions` maps each region to the burned fraction of that region (0…1).
    public static func totalBSA(fractions: [BurnRegion: Double], ageYears: Double?) -> Double {
        let total = fractions.reduce(0.0) { partial, entry in
            partial + percentage(of: entry.key, ageYears: ageYears) * entry.value.clamped(to: 0...1)
        }
        return min(total, 100)
    }
}

public enum BurnFormula: String, Codable, Sendable, CaseIterable, Identifiable {
    case parkland4
    case atlsAdult2
    case atlsChild3

    public var id: String { rawValue }

    public var mLPerKgPerPercent: Double {
        switch self {
        case .parkland4: 4
        case .atlsAdult2: 2
        case .atlsChild3: 3
        }
    }

    public var label: String {
        switch self {
        case .parkland4: "Parkland klasik / luka bakar listrik (4 mL)"
        case .atlsAdult2: "ATLS 10 dewasa (2 mL)"
        case .atlsChild3: "ATLS 10 anak ≤ 14 thn (3 mL)"
        }
    }
}

public struct ParklandPlan: Sendable, Hashable {
    public let totalML: Double
    public let firstHalfML: Double
    public let secondHalfML: Double
    public let hoursSinceBurn: Double
    public let alreadyGivenML: Double
    /// Volume still due within the first 8 h window.
    public let remainingFirstPeriodML: Double
    /// Hours left in the first 8 h window (0 if elapsed).
    public let remainingFirstPeriodHours: Double
    public let firstPeriodRate: RateTriple
    public let secondPeriodRate: RateTriple
    /// Target urine output (mL/jam).
    public let urineOutputTargetML: ClosedRange<Double>
    public let alerts: [SafetyAlert]
}

public enum ParklandCalculator {
    /// - Parameters:
    ///   - hoursSinceBurn: time elapsed since the burn (Waktu Kejadian), not since arrival.
    ///   - alreadyGivenML: crystalloid already given pre-hospital / at another facility.
    public static func plan(
        weightKg: Double,
        tbsaPercent: Double,
        hoursSinceBurn: Double,
        alreadyGivenML: Double = 0,
        formula: BurnFormula = .parkland4,
        isChild: Bool = false,
        isElectrical: Bool = false
    ) -> ParklandPlan? {
        guard weightKg > 0, tbsaPercent > 0, tbsaPercent <= 100, hoursSinceBurn >= 0 else { return nil }
        let given = max(alreadyGivenML, 0)
        let total = formula.mLPerKgPerPercent * weightKg * tbsaPercent
        let firstHalf = total / 2
        let secondHalf = total / 2
        var alerts: [SafetyAlert] = []

        let remainingHours = max(8 - hoursSinceBurn, 0)
        var remainingFirst = max(firstHalf - given, 0)
        let firstRate: Double
        var secondRate = secondHalf / 16

        if remainingHours > 0 {
            firstRate = remainingFirst / remainingHours
        } else {
            // First 8 h elapsed: give the outstanding first-half deficit together with the
            // second half over the remaining time to 24 h.
            let hoursTo24 = max(24 - hoursSinceBurn, 1)
            let outstanding = max(total - given, 0)
            secondRate = outstanding / hoursTo24
            remainingFirst = 0
            firstRate = 0
            alerts.append(SafetyAlert(.burnWindowElapsed, .warning, title: "8 jam pertama sudah lewat",
                                      message: "Sisa volume \(ClinicalFormat.volume(outstanding)) mL dibagi \(ClinicalFormat.number(hoursTo24, maxDecimals: 1)) jam tersisa hingga 24 jam. Titrasi berdasarkan produksi urin."))
        }

        let threshold = isChild ? 10.0 : 20.0
        if tbsaPercent < threshold {
            alerts.append(SafetyAlert(.burnBelowFormalResuscitationThreshold, .info, title: "TBSA < \(ClinicalFormat.number(threshold))%",
                                      message: "Resusitasi formula umumnya untuk luka bakar derajat II–III ≥ \(ClinicalFormat.number(threshold))% TBSA. Hanya hitung derajat II (partial) dan III (full thickness)."))
        }

        let urine: ClosedRange<Double>
        if isElectrical {
            urine = (weightKg * 1)...(weightKg * 1.5)
        } else if isChild && weightKg < 30 {
            urine = (weightKg * 1)...(weightKg * 1)
        } else {
            urine = (weightKg * 0.5)...(weightKg * 0.5)
        }

        return ParklandPlan(
            totalML: total,
            firstHalfML: firstHalf,
            secondHalfML: secondHalf,
            hoursSinceBurn: hoursSinceBurn,
            alreadyGivenML: given,
            remainingFirstPeriodML: remainingFirst,
            remainingFirstPeriodHours: remainingHours,
            firstPeriodRate: RateTriple(mLPerHour: firstRate),
            secondPeriodRate: RateTriple(mLPerHour: secondRate),
            urineOutputTargetML: urine,
            alerts: alerts.sortedBySeverity()
        )
    }
}
