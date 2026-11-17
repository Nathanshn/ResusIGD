import Foundation

/// Pediatric resuscitation equipment and energy doses for a given weight / age (APLS / PALS rules of thumb).
public struct ResuscitationEquipment: Sendable, Hashable {
    public let weightKg: Double
    public let ageMonthsUsed: Double
    /// True when no age was available and an "equivalent age" was derived from weight.
    public let ageDerivedFromWeight: Bool
    public let ettUncuffedID: Double
    public let ettCuffedID: Double
    public let ettDepthCm: Double
    public let ettDepthFormula: String
    public let laryngoscope: String
    public let lmaSize: Double
    public let defibrillationFirstJ: Double
    public let defibrillationSubsequentJ: Double
    public let cardioversionLowJ: Double
    public let cardioversionHighJ: Double
    public let cardioversionEscalationJ: Double
    public let epinephrineArrestMg: Double
    /// Volume of epinephrine 1:10.000 (0,1 mg/mL).
    public let epinephrineArrestML: Double

    /// Maximum energy delivered regardless of weight (adult biphasic dose).
    public static let adultMaxEnergyJ = 200.0

    public static func calculate(weightKg: Double, ageMonths: Double?) -> ResuscitationEquipment? {
        guard weightKg > 0, weightKg.isFinite else { return nil }
        let derived = ageMonths == nil
        let age = ageMonths ?? PediatricWeightEstimator.equivalentAgeMonths(forWeightKg: weightKg)
        let tubes = ettSizes(ageMonths: age, weightKg: weightKg)
        let depth = ettDepth(ageMonths: age, weightKg: weightKg, uncuffedID: tubes.uncuffed)
        let epiMg = min(0.01 * weightKg, 1.0)

        return ResuscitationEquipment(
            weightKg: weightKg,
            ageMonthsUsed: age,
            ageDerivedFromWeight: derived,
            ettUncuffedID: tubes.uncuffed,
            ettCuffedID: tubes.cuffed,
            ettDepthCm: depth.cm,
            ettDepthFormula: depth.formula,
            laryngoscope: laryngoscope(ageMonths: age),
            lmaSize: lmaSize(weightKg: weightKg),
            defibrillationFirstJ: energy(2, weightKg),
            defibrillationSubsequentJ: energy(4, weightKg),
            cardioversionLowJ: energy(0.5, weightKg),
            cardioversionHighJ: energy(1, weightKg),
            cardioversionEscalationJ: energy(2, weightKg),
            epinephrineArrestMg: epiMg,
            epinephrineArrestML: epiMg * 10
        )
    }

    /// Rounds to nearest 0,5 with ties going DOWN (conservative: smaller tube).
    static func roundTubeSize(_ value: Double) -> Double {
        ((value * 2) - 1e-9).rounded(.toNearestOrAwayFromZero) / 2
    }

    static func ettSizes(ageMonths: Double, weightKg: Double) -> (uncuffed: Double, cuffed: Double) {
        if ageMonths < 1 {
            // Neonate (NRP weight bands)
            if weightKg < 1 { return (2.5, 2.5) }
            if weightKg < 2 { return (3.0, 3.0) }
            return (3.5, 3.0)
        }
        if ageMonths < 6 { return (3.5, 3.0) }
        if ageMonths < 12 { return (4.0, 3.5) }
        let years = (ageMonths / 12).rounded(.down)
        let uncuffed = min(roundTubeSize(years / 4 + 4), 8.0)
        let cuffed = min(roundTubeSize(years / 4 + 3.5), 8.0)
        return (uncuffed, cuffed)
    }

    static func ettDepth(ageMonths: Double, weightKg: Double, uncuffedID: Double) -> (cm: Double, formula: String) {
        if ageMonths < 1 {
            return ((weightKg + 6).rounded(toStep: 0.5), "Neonatus: BB (kg) + 6 cm")
        }
        if ageMonths < 12 {
            return ((uncuffedID * 3).rounded(toStep: 0.5), "Bayi: ID ETT × 3")
        }
        let years = (ageMonths / 12).rounded(.down)
        return ((years / 2 + 12).rounded(toStep: 0.5), "Usia (thn)/2 + 12 cm (oral, di bibir)")
    }

    static func laryngoscope(ageMonths: Double) -> String {
        switch ageMonths {
        case ..<1: "Miller 0 (prematur) / Miller 1 (aterm) — bilah lurus"
        case ..<12: "Miller 1 — bilah lurus"
        case ..<24: "Miller 1–2 (lurus) atau Macintosh 1–2"
        case ..<72: "Macintosh 2 atau Miller 2"
        case ..<144: "Macintosh 2–3 atau Miller 2"
        default: "Macintosh 3 (Macintosh 4 untuk postur besar)"
        }
    }

    static func lmaSize(weightKg: Double) -> Double {
        switch weightKg {
        case ..<5: 1
        case ..<10: 1.5
        case ..<20: 2
        case ..<30: 2.5
        case ..<50: 3
        case ..<70: 4
        case ..<100: 5
        default: 6
        }
    }

    static func energy(_ joulesPerKg: Double, _ weightKg: Double) -> Double {
        min((joulesPerKg * weightKg).rounded(.toNearestOrAwayFromZero), adultMaxEnergyJ)
    }
}
