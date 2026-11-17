import Foundation
import Observation
import ClinicalCore

/// Module 3 — offline guideline search.
@MainActor
@Observable
final class GuidelineListViewModel {
    private(set) var guidelines: [Guideline] = []
    var query = ""
    var category: GuidelineCategory?

    func load(guidelines: [Guideline]) {
        guard self.guidelines != guidelines else { return }
        self.guidelines = guidelines
    }

    var results: [Guideline] {
        let pool = category.map { selected in guidelines.filter { $0.category == selected } } ?? guidelines
        return FuzzySearch.searchGuidelines(pool, query: query)
    }

    var categoriesInUse: [GuidelineCategory] {
        GuidelineCategory.allCases.filter { category in guidelines.contains { $0.category == category } }
    }
}

/// Rule of Nines + Parkland calculator embedded in the burn guideline.
@MainActor
@Observable
final class BurnCalculatorViewModel {
    var weightText = ""
    var ageText = ""
    var fractions: [BurnRegion: Double] = [:]
    var manualTBSAText = ""
    var useManualTBSA = false
    var formula: BurnFormula = .parkland4
    var isElectrical = false
    var burnTime = Date().addingTimeInterval(-3600)
    var alreadyGivenText = ""

    var weightKg: Double? { ClinicalFormat.parse(weightText) }
    var ageYears: Double? { ClinicalFormat.parse(ageText) }
    var isChild: Bool { (ageYears ?? 18) <= 14 }

    func fraction(for region: BurnRegion) -> Double { fractions[region] ?? 0 }
    func setFraction(_ value: Double, for region: BurnRegion) { fractions[region] = value }

    var tbsa: Double {
        if useManualTBSA { return min(max(ClinicalFormat.parse(manualTBSAText) ?? 0, 0), 100) }
        return RuleOfNines.totalBSA(fractions: fractions, ageYears: ageYears)
    }

    func hoursSinceBurn(now: Date) -> Double {
        max(0, now.timeIntervalSince(burnTime) / 3600)
    }

    func plan(now: Date) -> ParklandPlan? {
        guard let weightKg else { return nil }
        return ParklandCalculator.plan(
            weightKg: weightKg,
            tbsaPercent: tbsa,
            hoursSinceBurn: hoursSinceBurn(now: now),
            alreadyGivenML: ClinicalFormat.parse(alreadyGivenText) ?? 0,
            formula: formula,
            isChild: isChild,
            isElectrical: isElectrical
        )
    }
}

/// Hyponatremia + KCl drip calculators.
@MainActor
@Observable
final class ElectrolyteViewModel {
    // Sodium
    var sodiumText = ""
    var weightText = ""
    var ageText = ""
    var sex: Sex = .male
    var infusate: SodiumInfusate = .hypertonic3
    var highODSRisk = true

    // Potassium
    var potassiumText = ""
    var kclTotalText = "20"
    var kclVolumeText = "500"
    var kclRateText = "10"
    var access: VascularAccess = .peripheral

    var weightKg: Double? { ClinicalFormat.parse(weightText) }
    var ageYears: Double? { ClinicalFormat.parse(ageText) }

    var sodiumPlan: SodiumCorrectionPlan? {
        guard let sodium = ClinicalFormat.parse(sodiumText), let weightKg else { return nil }
        return ElectrolyteCalculator.sodiumCorrection(
            currentSodium: sodium, weightKg: weightKg, ageYears: ageYears ?? 40, sex: sex,
            infusate: infusate, maxRisePer24h: highODSRisk ? 8 : 10
        )
    }

    var potassiumPlan: ElectrolyteCalculator.PotassiumPlan? {
        guard let weightKg,
              let total = ClinicalFormat.parse(kclTotalText),
              let volume = ClinicalFormat.parse(kclVolumeText),
              let rate = ClinicalFormat.parse(kclRateText) else { return nil }
        return ElectrolyteCalculator.potassiumDrip(
            currentPotassium: ClinicalFormat.parse(potassiumText),
            totalMEq: total, volumeML: volume, rateMEqPerHour: rate,
            access: access, weightKg: weightKg, isChild: (ageYears ?? 40) < 18
        )
    }
}
