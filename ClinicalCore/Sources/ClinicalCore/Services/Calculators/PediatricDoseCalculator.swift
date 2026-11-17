import Foundation

public struct PediatricDoseResult: Sendable, Hashable {
    public let isValid: Bool
    /// Weight-based (or banded) dose before any cap.
    public let targetDoseMg: Double
    /// Final dose to administer after adult/daily caps and unit rounding.
    public let doseMg: Double
    public let mgPerKgSelected: Double?
    public let mgPerKgActual: Double
    /// Liquid formulations: volume to administer (mL).
    public let volumeML: Double?
    /// Unit formulations: number of tablets / suppositories / tubes.
    public let units: Double?
    public let unitName: String?
    public let dailyDoseMg: Double?
    public let cappedBy: [AlertCode]
    public let frequency: String
    public let route: DrugRoute
    public let administration: String
    public let alerts: [SafetyAlert]

    public var isCapped: Bool { !cappedBy.isEmpty }
}

/// Module 2 math engine: weight-based pediatric dosing with hard adult ceiling caps.
public enum PediatricDoseCalculator {
    /// Relative tolerance before a unit-rounding change is reported.
    public static let unitRoundingTolerance = 0.10

    public static func calculate(
        drug: PediatricDrug,
        regimen: PediatricRegimen,
        formulation: Formulation,
        weightKg: Double,
        ageMonths: Double?,
        mgPerKg chosenMgPerKg: Double? = nil
    ) -> PediatricDoseResult {
        var alerts: [SafetyAlert] = []
        var capped: [AlertCode] = []

        func invalid(_ alert: SafetyAlert) -> PediatricDoseResult {
            PediatricDoseResult(
                isValid: false, targetDoseMg: 0, doseMg: 0, mgPerKgSelected: chosenMgPerKg, mgPerKgActual: 0,
                volumeML: nil, units: nil, unitName: formulation.unitName, dailyDoseMg: nil, cappedBy: [],
                frequency: regimen.frequency, route: regimen.route, administration: regimen.administration,
                alerts: (alerts + [alert]).sortedBySeverity()
            )
        }

        guard weightKg > 0, weightKg.isFinite else {
            return invalid(SafetyAlert(.invalidInput, .danger, title: "Berat badan belum diisi",
                                       message: "Masukkan BB (kg) atau gunakan mode estimasi BB."))
        }
        guard regimen.formulationIDs.contains(formulation.id) else {
            return invalid(SafetyAlert(.invalidInput, .danger, title: "Sediaan tidak sesuai regimen",
                                       message: "\(formulation.label) tidak dipakai untuk regimen \(regimen.label)."))
        }

        alerts += applicabilityAlerts(regimen: regimen, weightKg: weightKg, ageMonths: ageMonths)

        // 1. Target dose
        let mgPerKgSelected: Double?
        var target: Double
        if let bands = regimen.fixedDoseBands, !bands.isEmpty {
            guard let band = bands.first(where: { $0.contains(weightKg) }) else {
                return invalid(SafetyAlert(.invalidInput, .danger, title: "BB di luar tabel dosis",
                                           message: "Tidak ada dosis tetap untuk BB \(ClinicalFormat.number(weightKg, maxDecimals: 1)) kg pada regimen ini."))
            }
            target = band.doseMg
            mgPerKgSelected = nil
        } else {
            guard let perKg = chosenMgPerKg ?? regimen.mgPerKgDefault, perKg > 0 else {
                return invalid(SafetyAlert(.invalidInput, .warning, title: "Dosis mg/kg belum diatur", message: "Pilih dosis mg/kg."))
            }
            mgPerKgSelected = perKg
            target = perKg * weightKg
            if let max = regimen.mgPerKgMax, perKg > max + 1e-9 {
                alerts.append(SafetyAlert(.doseAboveMaximum, .warning, title: "Di atas rentang mg/kg",
                                          message: "Rentang \(rangeText(regimen)) mg/kg; dipilih \(ClinicalFormat.dose(perKg)) mg/kg."))
            } else if let min = regimen.mgPerKgMin, perKg < min - 1e-9 {
                alerts.append(SafetyAlert(.doseBelowMinimum, .info, title: "Di bawah rentang mg/kg",
                                          message: "Rentang \(rangeText(regimen)) mg/kg; dipilih \(ClinicalFormat.dose(perKg)) mg/kg."))
            }
        }
        let targetDose = target

        // 2. Adult single-dose ceiling
        if let maxSingle = regimen.maxSingleDoseMg, target > maxSingle + 1e-9 {
            target = maxSingle
            capped.append(.cappedAtAdultSingleDose)
            alerts.append(SafetyAlert(.cappedAtAdultSingleDose, .warning, title: "DOSIS DIBATASI: maks dosis tunggal",
                                      message: "Hasil hitung \(ClinicalFormat.dose(targetDose)) mg melebihi dosis tunggal maksimal \(ClinicalFormat.dose(maxSingle)) mg (dosis dewasa). Dosis diberikan: \(ClinicalFormat.dose(maxSingle)) mg."))
        }

        // 3. Daily ceiling (mg/kg/hari and adult mg/hari)
        if let perDay = regimen.dosesPerDay, perDay > 0 {
            let limits = [regimen.maxDailyDoseMg, regimen.maxDailyMgPerKg.map { $0 * weightKg }].compactMap { $0 }
            if let dailyLimit = limits.min(), target * Double(perDay) > dailyLimit + 1e-9 {
                let before = target
                target = dailyLimit / Double(perDay)
                capped.append(.cappedAtDailyMaximum)
                alerts.append(SafetyAlert(.cappedAtDailyMaximum, .warning, title: "DOSIS DIBATASI: maks harian",
                                          message: "\(ClinicalFormat.dose(before)) mg × \(perDay)/hari melebihi batas harian \(ClinicalFormat.dose(dailyLimit)) mg/24 jam. Dosis per kali disesuaikan menjadi \(ClinicalFormat.dose(target)) mg."))
            }
        }

        // 4. Convert to formulation
        var volume: Double?
        var units: Double?
        var finalDose = target

        switch formulation.kind {
        case .liquid:
            guard let mgPerML = formulation.mgPerML, mgPerML > 0 else {
                return invalid(SafetyAlert(.invalidInput, .danger, title: "Konsentrasi sediaan tidak valid", message: formulation.label))
            }
            volume = target / mgPerML
        case .unit:
            guard let mgPerUnit = formulation.mgPerUnit, mgPerUnit > 0 else {
                return invalid(SafetyAlert(.invalidInput, .danger, title: "Kekuatan sediaan tidak valid", message: formulation.label))
            }
            let step = formulation.unitDivisibility ?? 1
            let exact = target / mgPerUnit
            let down = exact.floored(toStep: step)
            let up = down + step
            // Never round above the capped dose.
            let canRoundUp = (up * mgPerUnit) <= target * (1 + 1e-9)
            let chosen: Double
            if abs(up - exact) < abs(exact - down) && canRoundUp {
                chosen = up
            } else {
                chosen = down
            }
            guard chosen > 0 else {
                let name = formulation.unitName ?? "unit"
                return invalid(SafetyAlert(.unitRoundingChangedDose, .danger, title: "Sediaan terlalu besar",
                                           message: "Dosis \(ClinicalFormat.dose(target)) mg lebih kecil dari 1 \(name) \(ClinicalFormat.dose(mgPerUnit)) mg. Pilih sediaan lain (cair) atau kekuatan lebih kecil."))
            }
            units = chosen
            finalDose = chosen * mgPerUnit
            if target > 0, abs(finalDose - target) / target > unitRoundingTolerance {
                alerts.append(SafetyAlert(.unitRoundingChangedDose, .info, title: "Dosis disesuaikan dengan sediaan",
                                          message: "Target \(ClinicalFormat.dose(target)) mg → \(ClinicalFormat.number(chosen, maxDecimals: 2)) \(formulation.unitName ?? "unit") = \(ClinicalFormat.dose(finalDose)) mg (\(ClinicalFormat.dose(finalDose / weightKg)) mg/kg)."))
            }
            if let min = regimen.mgPerKgMin, !regimen.isWeightBanded, finalDose / weightKg < min - 1e-9 {
                alerts.append(SafetyAlert(.doseBelowMinimum, .warning, title: "Dosis efektif di bawah rentang",
                                          message: "Dengan sediaan ini dosis menjadi \(ClinicalFormat.dose(finalDose / weightKg)) mg/kg (< \(ClinicalFormat.dose(min)) mg/kg). Pertimbangkan sediaan cair."))
            }
        }

        let daily = regimen.dosesPerDay.map { finalDose * Double($0) }

        return PediatricDoseResult(
            isValid: true,
            targetDoseMg: targetDose,
            doseMg: finalDose,
            mgPerKgSelected: mgPerKgSelected,
            mgPerKgActual: finalDose / weightKg,
            volumeML: volume,
            units: units,
            unitName: formulation.unitName,
            dailyDoseMg: daily,
            cappedBy: capped,
            frequency: regimen.frequency,
            route: regimen.route,
            administration: regimen.administration,
            alerts: alerts.sortedBySeverity()
        )
    }

    static func applicabilityAlerts(regimen: PediatricRegimen, weightKg: Double, ageMonths: Double?) -> [SafetyAlert] {
        var alerts: [SafetyAlert] = []
        if let minAge = regimen.minAgeMonths, let ageMonths, ageMonths < minAge {
            alerts.append(SafetyAlert(.belowMinimumAge, .danger, title: "Di bawah usia minimal",
                                      message: "Regimen ini untuk usia ≥ \(ageText(months: minAge)). Usia pasien \(ageText(months: ageMonths))."))
        }
        if let minWeight = regimen.minWeightKg, weightKg < minWeight {
            alerts.append(SafetyAlert(.belowMinimumWeight, .warning, title: "Di bawah BB minimal regimen",
                                      message: "Regimen ini untuk BB ≥ \(ClinicalFormat.number(minWeight, maxDecimals: 1)) kg."))
        }
        if let maxWeight = regimen.maxWeightKg, weightKg >= maxWeight {
            alerts.append(SafetyAlert(.aboveMaximumWeight, .warning, title: "Di atas BB regimen",
                                      message: "Regimen ini untuk BB < \(ClinicalFormat.number(maxWeight, maxDecimals: 1)) kg; pilih regimen lain."))
        }
        return alerts
    }

    static func rangeText(_ regimen: PediatricRegimen) -> String {
        let low = regimen.mgPerKgMin.map(ClinicalFormat.dose) ?? "?"
        let high = regimen.mgPerKgMax.map(ClinicalFormat.dose) ?? "?"
        return low == high ? low : "\(low)–\(high)"
    }

    static func ageText(months: Double) -> String {
        if months < 1 { return "\(ClinicalFormat.number(months * PatientAge.daysPerMonth, maxDecimals: 0)) hari" }
        if months < 24 { return "\(ClinicalFormat.number(months, maxDecimals: 0)) bulan" }
        return "\(ClinicalFormat.number(months / 12, maxDecimals: 1)) tahun"
    }
}
