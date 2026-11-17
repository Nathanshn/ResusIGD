import Foundation
import Observation
import ClinicalCore

/// Module 2 — pediatric patient, crash-weight estimation, resuscitation equipment & fluids.
@MainActor
@Observable
final class PediatricViewModel {
    private(set) var drugs: [PediatricDrug] = []

    // Patient inputs (text so "empty" ≠ 0)
    var weightText = ""
    var lengthText = ""
    var ageYearsText = ""
    var ageMonthsText = ""
    var ageDaysText = ""
    var sex: Sex = .male

    /// "BB Tidak Diketahui (Estimasi Emergensi)"
    var estimationMode = false
    var estimationMethod: WeightEstimationMethod = .lengthZone
    var bolusMLPerKg: Double = FluidCalculator.defaultBolusMLPerKg

    // Formulary filter
    var drugQuery = ""
    var categoryFilter: PediatricCategory?

    func load(drugs: [PediatricDrug]) {
        guard self.drugs != drugs else { return }
        self.drugs = drugs
    }

    // MARK: Patient

    var lengthCm: Double? { ClinicalFormat.parse(lengthText) }

    /// nil when no age field has been filled.
    var age: PatientAge? {
        let fields = [ageYearsText, ageMonthsText, ageDaysText].map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.contains(where: { !$0.isEmpty }) else { return nil }
        return PatientAge(
            years: Self.wholeNumber(ageYearsText, max: 120),
            months: Self.wholeNumber(ageMonthsText, max: 240),
            days: Self.wholeNumber(ageDaysText, max: 400)
        )
    }

    /// Parses a non-negative whole number, clamped so absurd input can never trap `Int(_:)`.
    private static func wholeNumber(_ text: String, max upper: Double) -> Int {
        let value = ClinicalFormat.parse(text) ?? 0
        return Int(min(max(value, 0), upper).rounded(.down))
    }

    var ageMonths: Double? { age?.totalMonths }

    var enteredWeightKg: Double? { ClinicalFormat.parse(weightText) }

    var estimate: WeightEstimate? {
        guard estimationMode else { return nil }
        switch estimationMethod {
        case .lengthZone: return lengthCm.flatMap(PediatricWeightEstimator.lengthZone(lengthCm:))
        case .traubJohnson: return lengthCm.flatMap(PediatricWeightEstimator.traubJohnson(lengthCm:))
        case .apls: return ageMonths.flatMap(PediatricWeightEstimator.apls(ageMonths:))
        case .luscombeOwens: return ageMonths.flatMap(PediatricWeightEstimator.luscombeOwens(ageMonths:))
        }
    }

    /// Weight used for every calculation: estimated in crash mode, otherwise the measured weight.
    var weightKg: Double? {
        if estimationMode { return estimate?.weightKg }
        guard let entered = enteredWeightKg, entered > 0 else { return nil }
        return entered
    }

    var estimationNeedsInput: String? {
        guard estimationMode, estimate == nil else { return nil }
        switch estimationMethod {
        case .lengthZone, .traubJohnson: return "Masukkan panjang/tinggi badan (cm)."
        case .apls, .luscombeOwens: return "Masukkan usia pasien."
        }
    }

    var patientAlerts: [SafetyAlert] {
        var alerts: [SafetyAlert] = []
        if !estimationMode {
            alerts += InputPlausibility.pediatric(weightKg: enteredWeightKg, ageMonths: ageMonths, lengthCm: lengthCm)
        }
        if let estimate, estimate.outsideValidatedRange {
            alerts.append(SafetyAlert(.ageOutOfFormulaRange, .warning, title: "Di luar rentang validasi formula", message: estimate.note))
        }
        return alerts.sortedBySeverity()
    }

    // MARK: Resuscitation outputs

    var equipment: ResuscitationEquipment? {
        guard let weightKg else { return nil }
        return ResuscitationEquipment.calculate(weightKg: weightKg, ageMonths: ageMonths)
    }

    var bolus: FluidBolus? {
        guard let weightKg else { return nil }
        return FluidCalculator.bolus(weightKg: weightKg, mLPerKg: bolusMLPerKg)
    }

    var maintenance: MaintenanceFluid? {
        guard let weightKg else { return nil }
        return FluidCalculator.hollidaySegar(weightKg: weightKg)
    }

    // MARK: Formulary

    var filteredDrugs: [PediatricDrug] {
        let byCategory = categoryFilter.map { category in drugs.filter { $0.category == category } } ?? drugs
        return FuzzySearch.searchPediatricDrugs(byCategory, query: drugQuery)
    }
}

/// Dose calculation state for one pediatric drug (detail screen).
@MainActor
@Observable
final class PediatricDoseViewModel {
    let drug: PediatricDrug
    private(set) var regimenID: String
    private(set) var formulationID: String
    var mgPerKg: Double

    init(drug: PediatricDrug) {
        self.drug = drug
        let regimen = drug.regimens.first
        self.regimenID = regimen?.id ?? ""
        self.formulationID = regimen.flatMap { drug.formulations(for: $0).first?.id } ?? ""
        self.mgPerKg = regimen?.mgPerKgDefault ?? 0
    }

    var regimen: PediatricRegimen? { drug.regimens.first { $0.id == regimenID } }
    var formulations: [Formulation] { regimen.map(drug.formulations(for:)) ?? [] }
    var formulation: Formulation? { drug.formulations.first { $0.id == formulationID } }

    func selectRegimen(_ id: String) {
        regimenID = id
        guard let regimen else { return }
        mgPerKg = regimen.mgPerKgDefault ?? 0
        if !regimen.formulationIDs.contains(formulationID) {
            formulationID = drug.formulations(for: regimen).first?.id ?? ""
        }
    }

    func selectFormulation(_ id: String) {
        formulationID = id
    }

    var mgPerKgRange: ClosedRange<Double>? {
        guard let regimen, let low = regimen.mgPerKgMin, let high = regimen.mgPerKgMax else { return nil }
        // Allow 0 … 1,5 × max so above-range choices are possible but flagged.
        let upper = max(high * 1.5, low + 0.01)
        return 0...upper
    }

    var mgPerKgStep: Double {
        guard let high = regimen?.mgPerKgMax else { return 0.1 }
        switch high {
        case ..<0.05: return 0.001
        case ..<1: return 0.01
        case ..<10: return 0.1
        default: return 0.5
        }
    }

    func result(weightKg: Double?, ageMonths: Double?) -> PediatricDoseResult? {
        guard let regimen, let formulation, let weightKg else { return nil }
        return PediatricDoseCalculator.calculate(
            drug: drug, regimen: regimen, formulation: formulation,
            weightKg: weightKg, ageMonths: ageMonths,
            mgPerKg: regimen.isWeightBanded ? nil : mgPerKg
        )
    }
}
