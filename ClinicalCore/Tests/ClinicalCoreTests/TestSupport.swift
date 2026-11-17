import XCTest
@testable import ClinicalCore

/// Shared helpers: the bundled seed is loaded once and reused across tests.
enum Fixtures {
    static let seed: ClinicalSeed = {
        do { return try SeedRepository.loadBundled() } catch { fatalError("Seed failed to load: \(error)") }
    }()

    static func adult(_ id: String) -> AdultDrug {
        guard let drug = seed.adultDrugs.first(where: { $0.id == id }) else { fatalError("Missing adult drug \(id)") }
        return drug
    }

    static func adultRegimen(_ drugID: String, _ regimenID: String) -> (AdultDrug, AdultRegimen) {
        let drug = adult(drugID)
        guard let regimen = drug.regimens.first(where: { $0.id == regimenID }) else { fatalError("Missing regimen \(regimenID)") }
        return (drug, regimen)
    }

    static func pediatric(_ id: String) -> PediatricDrug {
        guard let drug = seed.pediatricDrugs.first(where: { $0.id == id }) else { fatalError("Missing pediatric drug \(id)") }
        return drug
    }

    static func pediatricDose(
        _ drugID: String, regimen regimenID: String, formulation formulationID: String,
        weightKg: Double, ageMonths: Double? = 60, mgPerKg: Double? = nil
    ) -> PediatricDoseResult {
        let drug = pediatric(drugID)
        guard let regimen = drug.regimens.first(where: { $0.id == regimenID }),
              let formulation = drug.formulations.first(where: { $0.id == formulationID }) else {
            fatalError("Missing \(drugID)/\(regimenID)/\(formulationID)")
        }
        return PediatricDoseCalculator.calculate(
            drug: drug, regimen: regimen, formulation: formulation,
            weightKg: weightKg, ageMonths: ageMonths, mgPerKg: mgPerKg
        )
    }
}

let accuracy = 1e-6
