import Foundation

// MARK: - Hyponatremia

public enum SodiumInfusate: String, Codable, Sendable, CaseIterable, Identifiable {
    case hypertonic3
    case nacl09
    case ringerLactate

    public var id: String { rawValue }

    /// Sodium content (mmol/L).
    public var sodiumMmolPerL: Double {
        switch self {
        case .hypertonic3: 513
        case .nacl09: 154
        case .ringerLactate: 130
        }
    }

    public var label: String {
        switch self {
        case .hypertonic3: "NaCl 3% (513 mmol/L)"
        case .nacl09: "NaCl 0,9% (154 mmol/L)"
        case .ringerLactate: "Ringer Laktat (130 mmol/L)"
        }
    }
}

public struct SodiumCorrectionPlan: Sendable, Hashable {
    public let totalBodyWaterL: Double
    public let tbwFactor: Double
    public let targetSodium: Double
    /// Na deficit to reach the 24-h target: TBW × (target − current).
    public let deficitMmol: Double
    /// Adrogué-Madias: expected rise in serum Na per 1 L of infusate.
    public let changePerLiter: Double
    /// Volume of infusate to achieve the 24-h target change (mL).
    public let volumeML: Double
    public let rate: RateTriple
    public let maxRisePer24h: Double
    public let alerts: [SafetyAlert]
}

public enum ElectrolyteCalculator {
    /// TBW fraction: children 0,6; adult men 0,6; adult women 0,5; elderly (≥ 65) men 0,5; elderly women 0,45.
    public static func tbwFactor(ageYears: Double, sex: Sex) -> Double {
        if ageYears < 18 { return 0.6 }
        if ageYears >= 65 { return sex == .male ? 0.5 : 0.45 }
        return sex == .male ? 0.6 : 0.5
    }

    /// Upper bound of correction-fluid volume considered realistic in 24 h (40 mL/kg, max 3 L).
    public static func maxPracticalVolumePer24hML(weightKg: Double) -> Double {
        min(40 * weightKg, 3000)
    }

    /// - Parameter maxRisePer24h: 8 mmol/L for high ODS risk (alcohol, malnutrition, hypokalemia, liver disease, Na ≤ 105), otherwise ≤ 10.
    public static func sodiumCorrection(
        currentSodium: Double,
        weightKg: Double,
        ageYears: Double,
        sex: Sex,
        infusate: SodiumInfusate = .hypertonic3,
        maxRisePer24h: Double = 8
    ) -> SodiumCorrectionPlan? {
        guard weightKg > 0, currentSodium > 90, currentSodium < 180, maxRisePer24h > 0 else { return nil }
        let factor = tbwFactor(ageYears: ageYears, sex: sex)
        let tbw = weightKg * factor
        var alerts: [SafetyAlert] = []

        if currentSodium >= 135 {
            alerts.append(SafetyAlert(.sodiumNotLow, .info, title: "Natrium tidak rendah",
                                      message: "Na \(ClinicalFormat.number(currentSodium)) mmol/L (≥ 135). Koreksi tidak diperlukan."))
            return SodiumCorrectionPlan(totalBodyWaterL: tbw, tbwFactor: factor, targetSodium: currentSodium, deficitMmol: 0,
                                        changePerLiter: 0, volumeML: 0, rate: RateTriple(mLPerHour: 0),
                                        maxRisePer24h: maxRisePer24h, alerts: alerts)
        }

        let target = min(currentSodium + maxRisePer24h, 135)
        let deficit = tbw * (target - currentSodium)
        let changePerLiter = (infusate.sodiumMmolPerL - currentSodium) / (tbw + 1)
        let volumeL = changePerLiter > 0 ? (target - currentSodium) / changePerLiter : 0
        let volumeML = volumeL * 1000

        if currentSodium < 120 {
            alerts.append(SafetyAlert(.sodiumSevere, .danger, title: "Hiponatremia berat (< 120)",
                                      message: "Bila gejala berat (kejang, penurunan kesadaran, distres kardiorespirasi): NaCl 3% 150 mL IV dalam 20 menit (anak 2 mL/kg, maks 100 mL), ulangi s.d. 2–3× hingga Na naik 5 mmol/L. Periksa Na tiap 20 menit pada fase ini."))
        }
        alerts.append(SafetyAlert(.correctionLimit, .warning, title: "Batas koreksi aman",
                                  message: "Kenaikan Na maks \(ClinicalFormat.number(maxRisePer24h)) mmol/L dalam 24 jam pertama (≤ 18 mmol/L dalam 48 jam) untuk mencegah sindrom demielinasi osmotik. Cek Na tiap 4–6 jam; waspadai koreksi berlebih akibat diuresis air."))
        if changePerLiter <= 0 {
            alerts.append(SafetyAlert(.invalidInput, .danger, title: "Cairan tidak menaikkan Na",
                                      message: "Kadar Na cairan ≤ Na serum; pilih cairan dengan Na lebih tinggi."))
        } else if volumeML > maxPracticalVolumePer24hML(weightKg: weightKg) {
            alerts.append(SafetyAlert(.impracticalVolume, .danger, title: "Volume tidak realistis",
                                      message: "Diperlukan ±\(ClinicalFormat.volume(volumeML)) mL \(infusate.label) dalam 24 jam — berisiko overload cairan. Gunakan NaCl 3% dan/atau tatalaksana penyebab (restriksi cairan, hentikan obat)."))
        }

        return SodiumCorrectionPlan(
            totalBodyWaterL: tbw, tbwFactor: factor, targetSodium: target, deficitMmol: deficit,
            changePerLiter: changePerLiter, volumeML: volumeML,
            rate: RateTriple(mLPerHour: volumeML / 24), maxRisePer24h: maxRisePer24h, alerts: alerts.sortedBySeverity()
        )
    }

    // MARK: - Hypokalemia

    public struct PotassiumPlan: Sendable, Hashable {
        public let concentrationMEqPerL: Double
        public let rate: RateTriple
        public let durationHours: Double
        public let ratePerKg: Double
        public let expectedRise: Double
        public let maxRateMEqPerHour: Double
        public let alerts: [SafetyAlert]
    }

    /// Maximum KCl infusion rates (mEq/jam).
    public static func maxPotassiumRate(access: VascularAccess, isChild: Bool, weightKg: Double) -> Double {
        if isChild { return min(0.5 * weightKg, access == .central ? 20 : 10) }
        return access == .central ? 20 : 10
    }

    /// Peripheral concentration ceiling (mEq/L).
    public static let peripheralMaxPotassiumMEqPerL = 40.0
    /// Central concentration ceiling usually accepted (mEq/L).
    public static let centralMaxPotassiumMEqPerL = 200.0

    /// KCl drip: `totalMEq` KCl diluted in `volumeML`, run at `rateMEqPerHour`.
    public static func potassiumDrip(
        currentPotassium: Double?,
        totalMEq: Double,
        volumeML: Double,
        rateMEqPerHour: Double,
        access: VascularAccess,
        weightKg: Double,
        isChild: Bool
    ) -> PotassiumPlan? {
        guard totalMEq > 0, volumeML > 0, rateMEqPerHour > 0, weightKg > 0 else { return nil }
        let concentrationPerL = totalMEq / volumeML * 1000
        let mLPerHour = rateMEqPerHour / concentrationPerL * 1000
        let maxRate = maxPotassiumRate(access: access, isChild: isChild, weightKg: weightKg)
        var alerts: [SafetyAlert] = []

        if let currentPotassium, currentPotassium >= 3.5 {
            alerts.append(SafetyAlert(.potassiumNotLow, .warning, title: "Kalium tidak rendah",
                                      message: "K \(ClinicalFormat.number(currentPotassium, maxDecimals: 1)) mEq/L (≥ 3,5). Pastikan indikasi koreksi IV."))
        }
        if rateMEqPerHour > maxRate + 1e-9 {
            alerts.append(SafetyAlert(.potassiumRateExceeded, .danger, title: "Laju KCl melebihi batas",
                                      message: "\(ClinicalFormat.number(rateMEqPerHour, maxDecimals: 1)) mEq/jam > batas \(ClinicalFormat.number(maxRate, maxDecimals: 1)) mEq/jam untuk \(access.label)\(isChild ? " (anak: 0,5 mEq/kg/jam)" : ""). Risiko aritmia/henti jantung."))
        } else if rateMEqPerHour > 10 {
            alerts.append(SafetyAlert(.potassiumRateExceeded, .warning, title: "Monitor EKG kontinu",
                                      message: "Laju > 10 mEq/jam memerlukan monitor EKG kontinu dan CVC."))
        }
        let concentrationLimit = access == .peripheral ? peripheralMaxPotassiumMEqPerL : centralMaxPotassiumMEqPerL
        if concentrationPerL > concentrationLimit + 1e-9 {
            alerts.append(SafetyAlert(.potassiumConcentrationExceeded, access == .peripheral ? .warning : .danger,
                                      title: "Konsentrasi KCl tinggi",
                                      message: "\(ClinicalFormat.number(concentrationPerL)) mEq/L > \(ClinicalFormat.number(concentrationLimit)) mEq/L untuk \(access.label). Risiko flebitis/nyeri; encerkan atau gunakan CVC."))
        }

        return PotassiumPlan(
            concentrationMEqPerL: concentrationPerL,
            rate: RateTriple(mLPerHour: mLPerHour),
            durationHours: totalMEq / rateMEqPerHour,
            ratePerKg: rateMEqPerHour / weightKg,
            expectedRise: totalMEq / 10 * 0.1,
            maxRateMEqPerHour: maxRate,
            alerts: alerts.sortedBySeverity()
        )
    }

    // MARK: - Alteplase (stroke)

    public struct AlteplasePlan: Sendable, Hashable {
        public let totalMg: Double
        public let bolusMg: Double
        public let infusionMg: Double
        /// At the standard reconstitution of 1 mg/mL.
        public let bolusML: Double
        public let infusionML: Double
        public let infusionRateMLPerHour: Double
        public let wasCapped: Bool
        public let alerts: [SafetyAlert]
    }

    public static let alteplaseMgPerKg = 0.9
    public static let alteplaseMaxMg = 90.0

    /// Acute ischemic stroke: 0,9 mg/kg (max 90 mg); 10% IV bolus over 1 min, 90% infusion over 60 min.
    public static func alteplase(weightKg: Double) -> AlteplasePlan? {
        guard weightKg > 0 else { return nil }
        let raw = alteplaseMgPerKg * weightKg
        let total = min(raw, alteplaseMaxMg)
        let bolus = total * 0.1
        let infusion = total - bolus
        var alerts: [SafetyAlert] = []
        if raw > alteplaseMaxMg {
            alerts.append(SafetyAlert(.alteplaseCapped, .warning, title: "Dosis dibatasi 90 mg",
                                      message: "0,9 mg/kg × \(ClinicalFormat.number(weightKg, maxDecimals: 1)) kg = \(ClinicalFormat.dose(raw)) mg; dosis maksimal 90 mg."))
        }
        return AlteplasePlan(totalMg: total, bolusMg: bolus, infusionMg: infusion, bolusML: bolus, infusionML: infusion,
                             infusionRateMLPerHour: infusion, wasCapped: raw > alteplaseMaxMg, alerts: alerts)
    }
}
