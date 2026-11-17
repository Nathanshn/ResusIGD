import XCTest
@testable import ClinicalCore

final class PediatricDoseCalculatorTests: XCTestCase {
    // MARK: Normal cases

    func testParacetamolSyrup120_10kg_15mgKg() {
        let r = Fixtures.pediatricDose("paracetamol", regimen: "oral", formulation: "syr120", weightKg: 10, mgPerKg: 15)
        XCTAssertTrue(r.isValid)
        XCTAssertEqual(r.doseMg, 150, accuracy: accuracy)
        XCTAssertEqual(r.volumeML ?? 0, 6.25, accuracy: accuracy)                 // 150 ÷ 24 mg/mL
        XCTAssertEqual(r.dailyDoseMg ?? 0, 600, accuracy: accuracy)
        XCTAssertFalse(r.isCapped, "600 mg/day equals 60 mg/kg/day — at, not over, the limit")
    }

    func testSameDoseDifferentFormulations_giveDifferentVolumes() {
        let syrup = Fixtures.pediatricDose("paracetamol", regimen: "oral", formulation: "syr250", weightKg: 10, mgPerKg: 15)
        let drops = Fixtures.pediatricDose("paracetamol", regimen: "oral", formulation: "drops", weightKg: 10, mgPerKg: 15)
        XCTAssertEqual(syrup.doseMg, drops.doseMg, accuracy: accuracy)
        XCTAssertEqual(syrup.volumeML ?? 0, 3, accuracy: accuracy)
        XCTAssertEqual(drops.volumeML ?? 0, 1.5, accuracy: accuracy)
    }

    func testDefaultMgPerKgUsedWhenNotProvided() {
        let r = Fixtures.pediatricDose("ondansetron", regimen: "iv", formulation: "inj", weightKg: 20)
        XCTAssertEqual(r.mgPerKgSelected ?? 0, 0.15, accuracy: accuracy)
        XCTAssertEqual(r.doseMg, 3, accuracy: accuracy)
        XCTAssertEqual(r.volumeML ?? 0, 1.5, accuracy: accuracy)
    }

    func testEpinephrine1to10000_arrest() {
        let r = Fixtures.pediatricDose("epinefrin-anak", regimen: "henti-jantung", formulation: "dil10000", weightKg: 15)
        XCTAssertEqual(r.doseMg, 0.15, accuracy: accuracy)
        XCTAssertEqual(r.volumeML ?? 0, 1.5, accuracy: accuracy)                  // 0,1 mL/kg
        XCTAssertEqual(r.route, .intravena)
    }

    // MARK: Adult ceiling caps

    func testParacetamol_80kg_cappedAtAdultSingleDose() {
        let r = Fixtures.pediatricDose("paracetamol", regimen: "oral", formulation: "syr250", weightKg: 80, ageMonths: 180, mgPerKg: 15)
        XCTAssertEqual(r.targetDoseMg, 1200, accuracy: accuracy)
        XCTAssertEqual(r.doseMg, 1000, accuracy: accuracy)
        XCTAssertEqual(r.cappedBy, [.cappedAtAdultSingleDose])
        XCTAssertTrue(r.alerts.contains(.cappedAtAdultSingleDose))
        XCTAssertEqual(r.volumeML ?? 0, 20, accuracy: accuracy)
    }

    func testEpinephrineArrest_neverExceeds1mg() {
        let r = Fixtures.pediatricDose("epinefrin-anak", regimen: "henti-jantung", formulation: "dil10000", weightKg: 120, ageMonths: 200)
        XCTAssertEqual(r.doseMg, 1, accuracy: accuracy)
        XCTAssertEqual(r.volumeML ?? 0, 10, accuracy: accuracy)
        XCTAssertTrue(r.isCapped)
    }

    func testPhenytoinLoading_cappedAt1000mg() {
        let r = Fixtures.pediatricDose("fenitoin", regimen: "loading", formulation: "inj", weightKg: 60, ageMonths: 168)
        XCTAssertEqual(r.targetDoseMg, 1200, accuracy: accuracy)
        XCTAssertEqual(r.doseMg, 1000, accuracy: accuracy)
        XCTAssertEqual(r.volumeML ?? 0, 20, accuracy: accuracy)
    }

    func testGentamicin_cappedAt500mg() {
        let r = Fixtures.pediatricDose("gentamisin", regimen: "sekali-sehari", formulation: "inj40", weightKg: 80, ageMonths: 200)
        XCTAssertEqual(r.doseMg, 500, accuracy: accuracy)
    }

    func testKetorolac_cappedByDailyMaximum() {
        // 0,5 mg/kg × 50 kg = 25 mg (< 30 single cap) but 25 × 4 = 100 > 90 mg/day → 22,5 mg
        let r = Fixtures.pediatricDose("ketorolac", regimen: "iv", formulation: "inj", weightKg: 50, ageMonths: 180)
        XCTAssertEqual(r.doseMg, 22.5, accuracy: accuracy)
        XCTAssertEqual(r.cappedBy, [.cappedAtDailyMaximum])
        XCTAssertEqual(r.dailyDoseMg ?? 0, 90, accuracy: accuracy)
    }

    func testDailyMgPerKgCap_whenUserChoosesHighDose() {
        // Paracetamol 20 mg/kg (above 15 range) × 4/day = 80 mg/kg/day > 60 → capped to 15 mg/kg
        let r = Fixtures.pediatricDose("paracetamol", regimen: "oral", formulation: "syr250", weightKg: 10, mgPerKg: 20)
        XCTAssertTrue(r.alerts.contains(.doseAboveMaximum))
        XCTAssertTrue(r.cappedBy.contains(.cappedAtDailyMaximum))
        XCTAssertEqual(r.doseMg, 150, accuracy: accuracy)
    }

    func testCappedDoseNeverExceedsAnyCeiling_acrossWeights() {
        let drug = Fixtures.pediatric("paracetamol")
        let regimen = drug.regimens.first { $0.id == "oral" }!
        let formulation = drug.formulations.first { $0.id == "syr250" }!
        for weight in stride(from: 2.0, through: 150.0, by: 0.5) {
            let r = PediatricDoseCalculator.calculate(drug: drug, regimen: regimen, formulation: formulation, weightKg: weight, ageMonths: 60, mgPerKg: 15)
            XCTAssertLessThanOrEqual(r.doseMg, 1000 + 1e-9)
            XCTAssertLessThanOrEqual((r.dailyDoseMg ?? 0), min(4000, 60 * weight) + 1e-6)
        }
    }

    // MARK: Fixed-dose bands & unit formulations

    func testRectalDiazepam_weightBands() {
        let small = Fixtures.pediatricDose("diazepam", regimen: "rektal", formulation: "rektal5", weightKg: 10)
        XCTAssertEqual(small.doseMg, 5, accuracy: accuracy)
        XCTAssertEqual(small.units ?? 0, 1, accuracy: accuracy)
        let boundary = Fixtures.pediatricDose("diazepam", regimen: "rektal", formulation: "rektal10", weightKg: 12)
        XCTAssertEqual(boundary.doseMg, 10, accuracy: accuracy, "≥ 12 kg → 10 mg")
        let twoTubes = Fixtures.pediatricDose("diazepam", regimen: "rektal", formulation: "rektal5", weightKg: 15)
        XCTAssertEqual(twoTubes.units ?? 0, 2, accuracy: accuracy)
        let tooBig = Fixtures.pediatricDose("diazepam", regimen: "rektal", formulation: "rektal10", weightKg: 10)
        XCTAssertFalse(tooBig.isValid, "10 mg tube for a 5 mg dose must be refused")
    }

    func testOndansetronOral_bands() {
        XCTAssertFalse(Fixtures.pediatricDose("ondansetron", regimen: "oral", formulation: "syr", weightKg: 7).isValid)
        let r = Fixtures.pediatricDose("ondansetron", regimen: "oral", formulation: "syr", weightKg: 20)
        XCTAssertEqual(r.doseMg, 4, accuracy: accuracy)
        XCTAssertEqual(r.volumeML ?? 0, 5, accuracy: accuracy)
        XCTAssertEqual(Fixtures.pediatricDose("ondansetron", regimen: "oral", formulation: "tab4", weightKg: 30).doseMg, 8, accuracy: accuracy)
    }

    func testSalbutamolNebul_bands() {
        XCTAssertEqual(Fixtures.pediatricDose("salbutamol", regimen: "nebul", formulation: "neb", weightKg: 18).volumeML ?? 0, 2.5, accuracy: accuracy)
        XCTAssertEqual(Fixtures.pediatricDose("salbutamol", regimen: "nebul", formulation: "neb", weightKg: 25).doseMg, 5, accuracy: accuracy)
    }

    func testSuppository_roundsDownToWholeUnit_andReportsChange() {
        // 12 kg × 15 = 180 mg; 125 mg supp → 1 supp (2 would be 250 mg > 180)
        let r = Fixtures.pediatricDose("paracetamol", regimen: "rektal", formulation: "supp125", weightKg: 12)
        XCTAssertEqual(r.units ?? 0, 1, accuracy: accuracy)
        XCTAssertEqual(r.doseMg, 125, accuracy: accuracy)
        XCTAssertTrue(r.alerts.contains(.unitRoundingChangedDose))
        let tooStrong = Fixtures.pediatricDose("paracetamol", regimen: "rektal", formulation: "supp250", weightKg: 12)
        XCTAssertFalse(tooStrong.isValid)
    }

    func testHalfTablet_neverRoundsAboveTarget() {
        // 40 kg × 15 = 600 mg; tablet 500 mg divisible by ½ → 1 tablet (1,5 = 750 > 600)
        let r = Fixtures.pediatricDose("paracetamol", regimen: "oral", formulation: "tab500", weightKg: 40, ageMonths: 144)
        XCTAssertEqual(r.units ?? 0, 1, accuracy: accuracy)
        XCTAssertLessThanOrEqual(r.doseMg, r.targetDoseMg)
    }

    // MARK: Applicability & invalid input

    func testIbuprofen_belowMinimumAge_isDanger() {
        let r = Fixtures.pediatricDose("ibuprofen", regimen: "oral", formulation: "syr100", weightKg: 5, ageMonths: 2)
        XCTAssertEqual(r.alerts.first { $0.code == .belowMinimumAge }?.level, .danger)
    }

    func testParacetamolIVInfant_aboveMaxWeightWarns() {
        let r = Fixtures.pediatricDose("paracetamol", regimen: "iv-bayi", formulation: "infus", weightKg: 12, ageMonths: 18)
        XCTAssertTrue(r.alerts.contains(.aboveMaximumWeight))
    }

    func testZeroWeight_isInvalid() {
        let r = Fixtures.pediatricDose("paracetamol", regimen: "oral", formulation: "syr120", weightKg: 0)
        XCTAssertFalse(r.isValid)
        XCTAssertEqual(r.doseMg, 0)
    }

    func testFormulationNotInRegimen_isInvalid() {
        let r = Fixtures.pediatricDose("paracetamol", regimen: "oral", formulation: "infus", weightKg: 10)
        XCTAssertFalse(r.isValid)
    }

    func testMgPerKgBelowRange_isInfo() {
        let r = Fixtures.pediatricDose("paracetamol", regimen: "oral", formulation: "syr120", weightKg: 10, mgPerKg: 5)
        XCTAssertEqual(r.alerts.first { $0.code == .doseBelowMinimum }?.level, .info)
    }
}

final class InputPlausibilityTests: XCTestCase {
    func testTypo120kgFor2YearOld_isDanger() {
        let alerts = InputPlausibility.pediatric(weightKg: 120, ageMonths: 24, lengthCm: nil)
        XCTAssertEqual(alerts.first { $0.code == .weightOutlierForAge }?.level, .danger)
    }

    func testPlausibleWeight_noAlert() {
        XCTAssertTrue(InputPlausibility.pediatric(weightKg: 12, ageMonths: 24, lengthCm: nil).isEmpty)
        XCTAssertTrue(InputPlausibility.pediatric(weightKg: 20, ageMonths: 24, lengthCm: nil).isEmpty, "ratio 1,67 below warning threshold")
    }

    func testModeratelyOff_isWarning() {
        let alerts = InputPlausibility.pediatric(weightKg: 30, ageMonths: 24, lengthCm: nil) // ratio 2,5
        XCTAssertEqual(alerts.first?.level, .warning)
        let low = InputPlausibility.pediatric(weightKg: 5, ageMonths: 24, lengthCm: nil)   // ratio 0,42
        XCTAssertEqual(low.first?.level, .warning)
    }

    func testLengthBasedCheck_whenAgeUnknown() {
        let alerts = InputPlausibility.pediatric(weightKg: 60, ageMonths: nil, lengthCm: 100) // Traub ≈ 15 kg
        XCTAssertEqual(alerts.first?.level, .danger)
    }

    func testAbsoluteLimits() {
        XCTAssertEqual(InputPlausibility.pediatric(weightKg: 0.1, ageMonths: nil, lengthCm: nil).first?.code, .weightImplausible)
        XCTAssertEqual(InputPlausibility.pediatric(weightKg: 400, ageMonths: nil, lengthCm: nil).first?.code, .weightImplausible)
    }

    func testAdultChecks() {
        XCTAssertTrue(InputPlausibility.adult(weightKg: 70, ageYears: 40).isEmpty)
        XCTAssertTrue(InputPlausibility.adult(weightKg: 7, ageYears: 40).contains(.weightOutlierForAge))
        XCTAssertTrue(InputPlausibility.adult(weightKg: 40, ageYears: 12).contains(.pediatricAgeInAdultModule))
    }
}
