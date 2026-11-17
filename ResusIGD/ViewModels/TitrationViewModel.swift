import Foundation
import Observation
import ClinicalCore

/// Module 1 — adult high-alert vasopressor & titration calculator.
@MainActor
@Observable
final class TitrationViewModel {
    private(set) var drugs: [AdultDrug] = []
    private(set) var selectedDrugID: String?
    private(set) var selectedRegimenID: String?

    // Patient
    var weightText = ""
    var ageText = ""
    var sex: Sex = .male

    // Preparation builder
    var ampouleMg: Double = 0
    var ampouleML: Double = 0
    var ampouleCount: Double = 1
    var finalVolumeML: Double = 50
    var diluent: Diluent = .nacl09
    var access: VascularAccess = .peripheral

    // Dose (infusion unit or mg for bolus)
    var dose: Double = 0

    // MARK: Setup

    func load(drugs: [AdultDrug]) {
        guard self.drugs != drugs else { return }
        self.drugs = drugs
        if selectedDrugID == nil || !drugs.contains(where: { $0.id == selectedDrugID }) {
            selectDrug(drugs.first?.id)
        }
    }

    func selectDrug(_ id: String?) {
        selectedDrugID = id
        guard let drug else { return }
        let defaults = InfusionPreparation.defaults(for: drug)
        ampouleMg = defaults.ampoule.mg
        ampouleML = defaults.ampoule.mL
        ampouleCount = defaults.ampouleCount
        finalVolumeML = defaults.finalVolumeML
        diluent = defaults.diluent
        access = defaults.access
        selectRegimen(drug.defaultRegimen?.id)
    }

    func selectRegimen(_ id: String?) {
        selectedRegimenID = id
        if let regimen { dose = regimen.defaultDose }
    }

    func resetPreparation() {
        selectDrug(selectedDrugID)
    }

    // MARK: Derived state

    var drug: AdultDrug? { drugs.first { $0.id == selectedDrugID } }
    var regimen: AdultRegimen? { drug?.regimens.first { $0.id == selectedRegimenID } }
    var weightKg: Double? { ClinicalFormat.parse(weightText) }
    var ageYears: Double? { ClinicalFormat.parse(ageText) }
    var isBolus: Bool { regimen?.mode == .bolus }

    var preparation: InfusionPreparation {
        InfusionPreparation(
            ampoule: AmpouleStrength(mg: ampouleMg, mL: ampouleML),
            ampouleCount: ampouleCount,
            finalVolumeML: finalVolumeML,
            diluent: diluent,
            access: access
        )
    }

    var isCustomAmpoule: Bool {
        guard let drug else { return false }
        return ampouleMg != drug.ampoule.mg || ampouleML != drug.ampoule.mL
    }

    var patientAlerts: [SafetyAlert] {
        InputPlausibility.adult(weightKg: weightKg, ageYears: ageYears)
    }

    var infusionResult: InfusionResult? {
        guard let drug, let regimen, regimen.mode == .infusion else { return nil }
        return InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: weightKg ?? 0, dose: dose, preparation: preparation)
    }

    var bolusResult: BolusResult? {
        guard let drug, let regimen, regimen.mode == .bolus else { return nil }
        return InfusionCalculator.bolus(drug: drug, regimen: regimen, doseMg: dose, ampoule: AmpouleStrength(mg: ampouleMg, mL: ampouleML))
    }

    /// All alerts for the current state, patient checks first, highest severity first.
    var alerts: [SafetyAlert] {
        let calc = infusionResult?.alerts ?? bolusResult?.alerts ?? []
        return (patientAlerts + calc).sortedBySeverity()
    }

    /// Slider range: 0 (or one step for bolus) up to the hard ceiling plus headroom so overdoses stay visible.
    var doseRange: ClosedRange<Double> {
        guard let regimen else { return 0...1 }
        let upper = regimen.sliderUpperBound
        let lower = regimen.mode == .bolus ? min(regimen.step, regimen.minDose) : 0
        let factor = regimen.mode == .bolus ? 1.5 : 1.25
        return lower...max(upper * factor, lower + regimen.step)
    }

    var usualRange: ClosedRange<Double>? {
        guard let regimen, regimen.maxDose >= regimen.minDose else { return nil }
        return regimen.minDose...regimen.maxDose
    }
}
