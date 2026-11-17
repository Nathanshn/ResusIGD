import Foundation

/// How the infusion is prepared at the bedside.
public struct InfusionPreparation: Sendable, Hashable {
    public var ampoule: AmpouleStrength
    public var ampouleCount: Double
    /// Total volume after dilution (drug + diluent), e.g. 50 mL syringe or 250 mL bag.
    public var finalVolumeML: Double
    public var diluent: Diluent
    public var access: VascularAccess

    public init(ampoule: AmpouleStrength, ampouleCount: Double, finalVolumeML: Double, diluent: Diluent, access: VascularAccess) {
        self.ampoule = ampoule
        self.ampouleCount = ampouleCount
        self.finalVolumeML = finalVolumeML
        self.diluent = diluent
        self.access = access
    }

    public static func defaults(for drug: AdultDrug) -> InfusionPreparation {
        let preferred = drug.diluentRules.first { $0.status == .preferred }?.diluent ?? .nacl09
        return InfusionPreparation(
            ampoule: drug.ampoule,
            ampouleCount: drug.defaultAmpouleCount,
            finalVolumeML: drug.defaultFinalVolumeML,
            diluent: preferred,
            access: drug.centralLinePreferred ? .central : .peripheral
        )
    }

    public var totalDrugMg: Double { ampoule.mg * ampouleCount }
    public var drugVolumeML: Double { ampoule.mL * ampouleCount }
    public var diluentVolumeML: Double { max(0, finalVolumeML - drugVolumeML) }
    public var concentrationMgPerML: Double { finalVolumeML > 0 ? totalDrugMg / finalVolumeML : 0 }
    public var isSyringe: Bool { finalVolumeML <= 60 }
}

public struct InfusionResult: Sendable, Hashable {
    public let isValid: Bool
    public let totalDrugMg: Double
    public let drugVolumeML: Double
    public let diluentVolumeML: Double
    public let concentrationMgPerML: Double
    public let concentrationDisplayValue: Double
    public let concentrationDisplayUnit: ConcentrationDisplayUnit
    public let mgPerMinute: Double
    public let rate: RateTriple
    /// How long one prepared syringe/bag lasts at this rate (hours). `nil` when rate is 0.
    public let hoursPerPreparation: Double?
    public let alerts: [SafetyAlert]
    public let preparationSteps: [String]

    public var rateMLPerHour: Double { rate.mLPerHour }
    public var macroDropsPerMinute: Double { rate.macroDropsPerMinute }
    public var microDropsPerMinute: Double { rate.microDropsPerMinute }
}

public struct BolusResult: Sendable, Hashable {
    public let isValid: Bool
    public let doseMg: Double
    /// Volume of undiluted ampoule solution containing the dose.
    public let undilutedVolumeML: Double
    public let ampoulesNeeded: Double
    public let maxCumulativeMg: Double?
    /// Number of full doses until the cumulative maximum is reached.
    public let dosesUntilCumulativeMax: Int?
    public let alerts: [SafetyAlert]
    public let steps: [String]
}

/// Module 1 math engine: continuous infusion titration and bolus preparation.
public enum InfusionCalculator {
    public static let standardFinalVolumes: [Double] = [50, 100, 250, 500]
    /// Below this pump rate, syringe pumps become imprecise.
    public static let minimumAccuratePumpRate = 0.5
    /// Below this duration one preparation runs out too fast for safe practice.
    public static let minimumHoursPerPreparation = 1.0

    // MARK: Infusion

    public static func calculate(
        drug: AdultDrug,
        regimen: AdultRegimen,
        weightKg: Double,
        dose: Double,
        preparation: InfusionPreparation
    ) -> InfusionResult {
        let unit = regimen.unit ?? .mgPerMin
        var alerts: [SafetyAlert] = []
        var isValid = true

        if unit.isWeightBased && !(weightKg > 0) {
            alerts.append(SafetyAlert(.invalidInput, .danger, title: "Berat badan belum diisi",
                                      message: "Dosis \(unit.label) memerlukan berat badan pasien (kg)."))
            isValid = false
        }
        if !(preparation.ampoule.mg > 0) || !(preparation.ampoule.mL > 0) || !(preparation.ampouleCount > 0) {
            alerts.append(SafetyAlert(.invalidInput, .danger, title: "Sediaan tidak valid",
                                      message: "Kekuatan ampul/vial dan jumlah ampul harus lebih dari 0."))
            isValid = false
        }
        if !(preparation.finalVolumeML > 0) {
            alerts.append(SafetyAlert(.invalidInput, .danger, title: "Volume akhir tidak valid",
                                      message: "Pilih volume akhir pengenceran (mL)."))
            isValid = false
        } else if preparation.drugVolumeML > preparation.finalVolumeML {
            alerts.append(SafetyAlert(.drugVolumeExceedsFinalVolume, .danger, title: "Volume obat melebihi volume akhir",
                                      message: "Volume obat \(ClinicalFormat.volume(preparation.drugVolumeML)) mL lebih besar dari volume akhir \(ClinicalFormat.volume(preparation.finalVolumeML)) mL. Kurangi jumlah ampul atau pilih volume lebih besar."))
            isValid = false
        }
        if !(dose > 0) {
            alerts.append(SafetyAlert(.invalidInput, .warning, title: "Dosis belum diatur",
                                      message: "Atur dosis \(unit.label) dengan slider atau stepper."))
            isValid = false
        }

        alerts += doseRangeAlerts(regimen: regimen, dose: dose, unitLabel: unit.label)
        alerts += diluentAlerts(drug: drug, diluent: preparation.diluent)

        let concentration = preparation.concentrationMgPerML
        let mgPerMinute = unit.mgPerMinute(dose: max(dose, 0), weightKg: max(weightKg, 0))
        let rawRate = (isValid && concentration > 0) ? mgPerMinute * 60 / concentration : 0
        let rate = RateTriple(mLPerHour: rawRate)
        let hours: Double? = rate.mLPerHour > 0 ? preparation.finalVolumeML / rate.mLPerHour : nil

        if concentration > 0 {
            alerts += accessAlerts(drug: drug, preparation: preparation, concentration: concentration)
        }

        if isValid {
            if rate.mLPerHour > 0 && rate.mLPerHour < minimumAccuratePumpRate {
                alerts.append(SafetyAlert(.pumpRateTooLow, .warning, title: "Laju terlalu rendah",
                                          message: "Laju \(ClinicalFormat.rate(rate.mLPerHour)) mL/jam kurang akurat pada syringe pump. Gunakan pengenceran lebih encer (volume akhir lebih besar atau ampul lebih sedikit)."))
            }
            if let hours, hours < minimumHoursPerPreparation {
                alerts.append(SafetyAlert(.pumpRateTooHigh, .warning, title: "Sediaan cepat habis",
                                          message: "Satu sediaan \(ClinicalFormat.volume(preparation.finalVolumeML)) mL habis dalam ±\(ClinicalFormat.number(hours * 60, maxDecimals: 0)) menit. Pertimbangkan konsentrasi lebih pekat dan siapkan sediaan berikutnya."))
            }
        }

        let displayUnit = drug.concentrationDisplayUnit
        let steps = isValid
            ? preparationSteps(drug: drug, regimen: regimen, preparation: preparation, rate: rate, displayUnit: displayUnit)
            : []

        return InfusionResult(
            isValid: isValid,
            totalDrugMg: preparation.totalDrugMg,
            drugVolumeML: preparation.drugVolumeML,
            diluentVolumeML: preparation.diluentVolumeML,
            concentrationMgPerML: concentration,
            concentrationDisplayValue: displayUnit.value(fromMgPerML: concentration),
            concentrationDisplayUnit: displayUnit,
            mgPerMinute: mgPerMinute,
            rate: rate,
            hoursPerPreparation: hours,
            alerts: alerts.sortedBySeverity(),
            preparationSteps: steps
        )
    }

    /// Reverse calculation: which dose is the patient receiving at a given pump rate?
    public static func dose(
        forRateMLPerHour rate: Double,
        concentrationMgPerML: Double,
        unit: InfusionDoseUnit,
        weightKg: Double
    ) -> Double {
        guard rate > 0, concentrationMgPerML > 0 else { return 0 }
        if unit.isWeightBased && !(weightKg > 0) { return 0 }
        let mgPerMinute = rate * concentrationMgPerML / 60
        return unit.dose(fromMgPerMinute: mgPerMinute, weightKg: weightKg)
    }

    // MARK: Bolus

    public static func bolus(drug: AdultDrug, regimen: AdultRegimen, doseMg: Double, ampoule: AmpouleStrength) -> BolusResult {
        var alerts: [SafetyAlert] = []
        var isValid = true
        if !(doseMg > 0) {
            alerts.append(SafetyAlert(.invalidInput, .warning, title: "Dosis belum diatur", message: "Atur dosis bolus (mg)."))
            isValid = false
        }
        if !(ampoule.mg > 0) || !(ampoule.mL > 0) {
            alerts.append(SafetyAlert(.invalidInput, .danger, title: "Sediaan tidak valid", message: "Kekuatan ampul harus lebih dari 0."))
            isValid = false
        }
        alerts += doseRangeAlerts(regimen: regimen, dose: doseMg, unitLabel: "mg")

        let volume = isValid ? doseMg / ampoule.mgPerML : 0
        let ampoules = isValid ? doseMg / ampoule.mg : 0
        var dosesUntilMax: Int?
        if let cumulative = regimen.maxCumulativeMg, doseMg > 0 {
            dosesUntilMax = Int((cumulative / doseMg + 1e-9).rounded(.down))
            alerts.append(SafetyAlert(.cumulativeBolusLimit, .info, title: "Batas dosis kumulatif",
                                      message: "Maksimal \(ClinicalFormat.dose(cumulative)) mg total (≈ \(dosesUntilMax ?? 0) × \(ClinicalFormat.dose(doseMg)) mg). Catat setiap pemberian di Code Timer."))
        }

        var steps: [String] = []
        if isValid {
            steps.append("Ambil \(ClinicalFormat.volume(volume)) mL dari ampul \(drug.name) \(ampoule.label) (≈ \(ClinicalFormat.number(ampoules, maxDecimals: 2)) ampul) = \(ClinicalFormat.dose(doseMg)) mg.")
            steps.append(regimen.administration)
            if let interval = regimen.repeatInterval {
                steps.append("Ulangi \(interval) bila diperlukan.")
            }
            steps += regimen.notes
        }

        return BolusResult(
            isValid: isValid,
            doseMg: doseMg,
            undilutedVolumeML: volume,
            ampoulesNeeded: ampoules,
            maxCumulativeMg: regimen.maxCumulativeMg,
            dosesUntilCumulativeMax: dosesUntilMax,
            alerts: alerts.sortedBySeverity(),
            steps: steps
        )
    }

    // MARK: Guardrails

    static func doseRangeAlerts(regimen: AdultRegimen, dose: Double, unitLabel: String) -> [SafetyAlert] {
        guard dose > 0 else { return [] }
        if let ceiling = regimen.hardCeilingDose, dose > ceiling {
            return [SafetyAlert(.doseAboveHardCeiling, .danger, title: "MELEBIHI DOSIS MAKSIMAL",
                                message: "Dosis \(ClinicalFormat.dose(dose)) \(unitLabel) melebihi batas atas \(ClinicalFormat.dose(ceiling)) \(unitLabel). Verifikasi ulang & konsultasikan DPJP/ICU; pertimbangkan obat tambahan.")]
        }
        if dose > regimen.maxDose {
            return [SafetyAlert(.doseAboveMaximum, .warning, title: "Di atas rentang lazim",
                                message: "Rentang lazim \(ClinicalFormat.dose(regimen.minDose))–\(ClinicalFormat.dose(regimen.maxDose)) \(unitLabel). Dosis saat ini \(ClinicalFormat.dose(dose)) \(unitLabel).")]
        }
        if dose < regimen.minDose {
            return [SafetyAlert(.doseBelowMinimum, .info, title: "Di bawah rentang lazim",
                                message: "Rentang lazim \(ClinicalFormat.dose(regimen.minDose))–\(ClinicalFormat.dose(regimen.maxDose)) \(unitLabel).")]
        }
        return []
    }

    static func diluentAlerts(drug: AdultDrug, diluent: Diluent) -> [SafetyAlert] {
        guard let rule = drug.rule(for: diluent) else {
            return [SafetyAlert(.diluentCaution, .warning, title: "Kompatibilitas \(diluent.shortLabel) belum terverifikasi",
                                message: "Data kompatibilitas \(drug.name) dengan \(diluent.label) tidak tersedia di database lokal. Konfirmasi ke farmasi.")]
        }
        switch rule.status {
        case .preferred:
            return []
        case .compatible:
            if let preferred = drug.diluentRules.first(where: { $0.status == .preferred && $0.diluent != diluent }) {
                return [SafetyAlert(.diluentPreferredAlternative, .info, title: "\(preferred.diluent.shortLabel) lebih dianjurkan",
                                    message: rule.note)]
            }
            return []
        case .caution:
            return [SafetyAlert(.diluentCaution, .warning, title: "Perhatian: \(diluent.shortLabel)", message: rule.note)]
        case .incompatible:
            return [SafetyAlert(.diluentIncompatible, .danger, title: "TIDAK KOMPATIBEL dengan \(diluent.shortLabel)", message: rule.note)]
        }
    }

    static func accessAlerts(drug: AdultDrug, preparation: InfusionPreparation, concentration: Double) -> [SafetyAlert] {
        var alerts: [SafetyAlert] = []
        let unit = drug.concentrationDisplayUnit
        if preparation.access == .peripheral {
            if let limit = drug.peripheralMaxConcentrationMgPerML, concentration > limit + 1e-12 {
                let level: AlertLevel = concentration > limit * 2 ? .danger : .warning
                alerts.append(SafetyAlert(.peripheralConcentrationExceeded, level, title: "Konsentrasi melebihi batas vena perifer",
                                          message: "\(ClinicalFormat.dose(unit.value(fromMgPerML: concentration))) \(unit.label) > batas perifer \(ClinicalFormat.dose(unit.value(fromMgPerML: limit))) \(unit.label). Gunakan CVC atau encerkan (tambah volume akhir / kurangi ampul)."))
            }
            if drug.centralLinePreferred {
                alerts.append(SafetyAlert(.centralLinePreferred, .warning, title: "CVC dianjurkan",
                                          message: "Jalur perifer hanya sementara: gunakan vena besar proksimal (antekubiti/lebih proksimal), kateter ≥ 20G, cek lokasi infus tiap 1–2 jam, dan rencanakan CVC."))
            }
            if let extravasation = drug.extravasationWarning {
                alerts.append(SafetyAlert(.extravasationRisk, .warning, title: "Risiko ekstravasasi", message: extravasation))
            }
        } else if let extravasation = drug.extravasationWarning {
            alerts.append(SafetyAlert(.extravasationRisk, .info, title: "Risiko ekstravasasi", message: extravasation))
        }
        return alerts
    }

    static func preparationSteps(
        drug: AdultDrug,
        regimen: AdultRegimen,
        preparation: InfusionPreparation,
        rate: RateTriple,
        displayUnit: ConcentrationDisplayUnit
    ) -> [String] {
        let count = ClinicalFormat.number(preparation.ampouleCount, maxDecimals: 2)
        let total = ClinicalFormat.dose(preparation.totalDrugMg)
        let drugML = ClinicalFormat.volume(preparation.drugVolumeML)
        let diluentML = ClinicalFormat.volume(preparation.diluentVolumeML)
        let finalML = ClinicalFormat.volume(preparation.finalVolumeML)
        let concentration = "\(ClinicalFormat.dose(displayUnit.value(fromMgPerML: preparation.concentrationMgPerML))) \(displayUnit.label)"

        var steps: [String] = []
        steps.append("Siapkan \(count) ampul \(drug.name) \(preparation.ampoule.label) → total \(total) mg dalam \(drugML) mL.")
        if preparation.isSyringe {
            steps.append("Isi spuit \(finalML) mL dengan \(diluentML) mL \(preparation.diluent.label), lalu tambahkan \(drugML) mL obat hingga total \(finalML) mL.")
        } else {
            steps.append("Dari kantong \(preparation.diluent.label) \(finalML) mL, buang \(drugML) mL cairan, lalu masukkan \(drugML) mL obat (total \(finalML) mL). Catatan: kantong infus sering berisi lebih dari volume label.")
        }
        steps.append("Campur dengan membolak-balik perlahan. Konsentrasi akhir: \(concentration).")
        steps.append("Beri label HIGH ALERT: nama obat, konsentrasi, tanggal/jam, paraf 2 petugas (double check).")
        if preparation.isSyringe {
            steps.append("Atur syringe pump \(ClinicalFormat.rate(rate.mLPerHour)) mL/jam.")
        } else {
            steps.append("Atur infusion pump \(ClinicalFormat.rate(rate.mLPerHour)) mL/jam, atau infus mikro \(ClinicalFormat.drops(rate.microDropsPerMinute)) tpm / makro \(ClinicalFormat.drops(rate.macroDropsPerMinute)) tpm bila pompa tidak tersedia.")
        }
        steps.append(regimen.administration)
        steps += regimen.notes
        steps += drug.preparationNotes
        return steps
    }
}
