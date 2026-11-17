import XCTest
@testable import ClinicalCore

final class InfusionCalculatorTests: XCTestCase {
    private func prep(_ drug: AdultDrug, amps: Double? = nil, volume: Double? = nil,
                      diluent: Diluent? = nil, access: VascularAccess = .central) -> InfusionPreparation {
        var p = InfusionPreparation.defaults(for: drug)
        if let amps { p.ampouleCount = amps }
        if let volume { p.finalVolumeML = volume }
        if let diluent { p.diluent = diluent }
        p.access = access
        return p
    }

    // MARK: Normal cases (hand-calculated)

    func testNorepinephrine_0_1mcgKgMin_70kg_4mgIn50mL() {
        let (drug, regimen) = Fixtures.adultRegimen("norepinefrin", "infus-syok")
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 0.1, preparation: prep(drug))
        XCTAssertTrue(r.isValid)
        XCTAssertEqual(r.concentrationMgPerML, 0.08, accuracy: accuracy)
        XCTAssertEqual(r.concentrationDisplayValue, 80, accuracy: accuracy)         // mcg/mL
        XCTAssertEqual(r.mgPerMinute, 0.007, accuracy: accuracy)
        XCTAssertEqual(r.rateMLPerHour, 5.25, accuracy: accuracy)                   // 0,42 mg/jam ÷ 0,08
        XCTAssertEqual(r.macroDropsPerMinute, 1.75, accuracy: accuracy)            // ÷ 3
        XCTAssertEqual(r.microDropsPerMinute, 5.25, accuracy: accuracy)            // = mL/jam
        XCTAssertEqual(r.hoursPerPreparation ?? 0, 50 / 5.25, accuracy: accuracy)
        XCTAssertEqual(r.diluentVolumeML, 46, accuracy: accuracy)
        XCTAssertFalse(r.preparationSteps.isEmpty)
    }

    func testDopamine_5mcgKgMin_70kg_200mgIn50mL() {
        let (drug, regimen) = Fixtures.adultRegimen("dopamin", "infus-hemodinamik")
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 5, preparation: prep(drug))
        XCTAssertEqual(r.concentrationMgPerML, 4, accuracy: accuracy)
        XCTAssertEqual(r.rateMLPerHour, 5.25, accuracy: accuracy)
    }

    func testDobutamine_10mcgKgMin_60kg() {
        let (drug, regimen) = Fixtures.adultRegimen("dobutamin", "infus-inotropik")
        // 250 mg / 50 mL = 5 mg/mL; 10 × 60 / 1000 = 0,6 mg/menit = 36 mg/jam → 7,2 mL/jam
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 60, dose: 10, preparation: prep(drug))
        XCTAssertEqual(r.rateMLPerHour, 7.2, accuracy: accuracy)
    }

    func testNicardipine_mgPerHour_isWeightIndependent() {
        let (drug, regimen) = Fixtures.adultRegimen("nicardipin", "infus-hipertensi")
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 0, dose: 5, preparation: prep(drug, access: .peripheral))
        XCTAssertTrue(r.isValid)
        XCTAssertEqual(r.concentrationMgPerML, 0.2, accuracy: accuracy)            // 50 mg / 250 mL
        XCTAssertEqual(r.rateMLPerHour, 25, accuracy: accuracy)
        XCTAssertFalse(r.alerts.contains(.peripheralConcentrationExceeded))        // exactly at limit
    }

    func testNitroglycerin_mcgPerMin() {
        let (drug, regimen) = Fixtures.adultRegimen("nitrogliserin", "infus-ska-edema-paru")
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 0, dose: 10, preparation: prep(drug))
        XCTAssertEqual(r.rateMLPerHour, 3, accuracy: accuracy)                     // 0,6 mg/jam ÷ 0,2 mg/mL
    }

    func testAmiodaroneMaintenance_1mgPerMin_900mgIn500mL() {
        let (drug, regimen) = Fixtures.adultRegimen("amiodaron", "infus-maintenance")
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 1, preparation: prep(drug, access: .peripheral))
        XCTAssertEqual(r.concentrationMgPerML, 1.8, accuracy: accuracy)
        XCTAssertEqual(r.rateMLPerHour, 60 / 1.8, accuracy: accuracy)
        XCTAssertEqual(r.macroDropsPerMinute, 60 / 1.8 / 3, accuracy: accuracy)
        XCTAssertFalse(r.alerts.contains(.peripheralConcentrationExceeded))        // 1,8 ≤ 2 mg/mL
    }

    func testEpinephrineBradycardia_mcgPerMin() {
        let (drug, regimen) = Fixtures.adultRegimen("epinefrin", "infus-bradikardia")
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 0, dose: 2, preparation: prep(drug))
        XCTAssertEqual(r.rateMLPerHour, 3, accuracy: accuracy)                     // 0,12 mg/jam ÷ 0,04 mg/mL
    }

    func testReverseCalculation_doseFromRate() {
        let dose = InfusionCalculator.dose(forRateMLPerHour: 5.25, concentrationMgPerML: 0.08, unit: .mcgPerKgPerMin, weightKg: 70)
        XCTAssertEqual(dose, 0.1, accuracy: accuracy)
        XCTAssertEqual(InfusionCalculator.dose(forRateMLPerHour: 5, concentrationMgPerML: 0.08, unit: .mcgPerKgPerMin, weightKg: 0), 0)
    }

    func testRoundTrip_allUnits() {
        for unit in InfusionDoseUnit.allCases {
            let mgPerMin = unit.mgPerMinute(dose: 7.5, weightKg: 82)
            XCTAssertEqual(unit.dose(fromMgPerMinute: mgPerMin, weightKg: 82), 7.5, accuracy: accuracy, unit.rawValue)
        }
    }

    // MARK: Guardrails

    func testPeripheralConcentration_dangerAboveTwiceLimit() {
        let (drug, regimen) = Fixtures.adultRegimen("norepinefrin", "infus-syok")
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 0.1, preparation: prep(drug, access: .peripheral))
        let alert = r.alerts.first { $0.code == .peripheralConcentrationExceeded }
        XCTAssertEqual(alert?.level, .danger)                                       // 80 mcg/mL vs 16
        XCTAssertTrue(r.alerts.contains(.centralLinePreferred))
        XCTAssertTrue(r.alerts.contains(.extravasationRisk))
        XCTAssertEqual(r.alerts.first?.level, .danger, "alerts sorted by severity")
    }

    func testPeripheralConcentration_warningBetweenLimitAndDouble() {
        let (drug, regimen) = Fixtures.adultRegimen("dopamin", "infus-hemodinamik")
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 5, preparation: prep(drug, access: .peripheral))
        XCTAssertEqual(r.alerts.first { $0.code == .peripheralConcentrationExceeded }?.level, .warning) // 4 vs 3,2 mg/mL
    }

    func testPeripheralConcentration_notRaisedOnCentralLine() {
        let (drug, regimen) = Fixtures.adultRegimen("norepinefrin", "infus-syok")
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 0.1, preparation: prep(drug, access: .central))
        XCTAssertFalse(r.alerts.contains(.peripheralConcentrationExceeded))
        XCTAssertEqual(r.alerts.first { $0.code == .extravasationRisk }?.level, .info)
    }

    func testDoseAboveUsualMaximum_isWarning_andAboveCeiling_isDanger() {
        let (drug, regimen) = Fixtures.adultRegimen("norepinefrin", "infus-syok")
        let p = prep(drug)
        let warning = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 0.7, preparation: p)
        XCTAssertEqual(warning.alerts.first { $0.code == .doseAboveMaximum }?.level, .warning)
        XCTAssertFalse(warning.alerts.contains(.doseAboveHardCeiling))
        let danger = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 1.2, preparation: p)
        XCTAssertEqual(danger.alerts.first { $0.code == .doseAboveHardCeiling }?.level, .danger)
        XCTAssertTrue(danger.isValid, "still calculates so the clinician sees the rate")
    }

    func testDoseExactlyAtBoundaries_noRangeAlert() {
        let (drug, regimen) = Fixtures.adultRegimen("dopamin", "infus-hemodinamik")
        for dose in [regimen.minDose, regimen.maxDose] {
            let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: dose, preparation: prep(drug))
            XCTAssertFalse(r.alerts.contains(.doseAboveMaximum))
            XCTAssertFalse(r.alerts.contains(.doseBelowMinimum))
            XCTAssertFalse(r.alerts.contains(.doseAboveHardCeiling))
        }
        let below = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 1, preparation: prep(drug))
        XCTAssertTrue(below.alerts.contains(.doseBelowMinimum))
    }

    func testDiluentCompatibility() {
        let (amio, amioRegimen) = Fixtures.adultRegimen("amiodaron", "infus-maintenance")
        let nacl = InfusionCalculator.calculate(drug: amio, regimen: amioRegimen, weightKg: 70, dose: 1, preparation: prep(amio, diluent: .nacl09))
        XCTAssertEqual(nacl.alerts.first { $0.code == .diluentCaution }?.level, .warning)
        let d5 = InfusionCalculator.calculate(drug: amio, regimen: amioRegimen, weightKg: 70, dose: 1, preparation: prep(amio, diluent: .dextrose5))
        XCTAssertFalse(d5.alerts.contains(.diluentCaution))

        let (ne, neRegimen) = Fixtures.adultRegimen("norepinefrin", "infus-syok")
        let neNacl = InfusionCalculator.calculate(drug: ne, regimen: neRegimen, weightKg: 70, dose: 0.1, preparation: prep(ne, diluent: .nacl09))
        XCTAssertEqual(neNacl.alerts.first { $0.code == .diluentPreferredAlternative }?.level, .info)
    }

    func testIncompatibleDiluent_isDanger() {
        var drug = Fixtures.adult("dopamin")
        drug.diluentRules = [DiluentRule(diluent: .nacl09, status: .compatible, note: "ok"),
                             DiluentRule(diluent: .dextrose5, status: .incompatible, note: "presipitasi")]
        let regimen = drug.regimens[0]
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 5, preparation: prep(drug, diluent: .dextrose5))
        XCTAssertEqual(r.alerts.first { $0.code == .diluentIncompatible }?.level, .danger)
    }

    func testMissingWeight_forWeightBasedDose_isInvalid() {
        let (drug, regimen) = Fixtures.adultRegimen("norepinefrin", "infus-syok")
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 0, dose: 0.1, preparation: prep(drug))
        XCTAssertFalse(r.isValid)
        XCTAssertEqual(r.rateMLPerHour, 0)
        XCTAssertTrue(r.alerts.contains(.invalidInput))
        XCTAssertTrue(r.preparationSteps.isEmpty)
    }

    func testDrugVolumeExceedingFinalVolume_isInvalid() {
        let (drug, regimen) = Fixtures.adultRegimen("norepinefrin", "infus-syok")
        let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 0.1, preparation: prep(drug, amps: 15, volume: 50))
        XCTAssertFalse(r.isValid)
        XCTAssertTrue(r.alerts.contains(.drugVolumeExceedsFinalVolume))
    }

    func testZeroAndNegativeInputs_areRejected() {
        let (drug, regimen) = Fixtures.adultRegimen("norepinefrin", "infus-syok")
        XCTAssertFalse(InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 0, preparation: prep(drug)).isValid)
        XCTAssertFalse(InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: -1, preparation: prep(drug)).isValid)
        XCTAssertFalse(InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 0.1, preparation: prep(drug, amps: 0)).isValid)
        XCTAssertFalse(InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: 0.1, preparation: prep(drug, volume: 0)).isValid)
        XCTAssertFalse(InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: .nan, dose: 0.1, preparation: prep(drug)).isValid)
    }

    func testPumpRateTooLow_andTooHigh() {
        let (drug, regimen) = Fixtures.adultRegimen("norepinefrin", "infus-syok")
        let low = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 40, dose: 0.01, preparation: prep(drug))
        XCTAssertEqual(low.rateMLPerHour, 0.3, accuracy: accuracy)
        XCTAssertTrue(low.alerts.contains(.pumpRateTooLow))
        let high = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 100, dose: 1.0, preparation: prep(drug))
        XCTAssertEqual(high.rateMLPerHour, 75, accuracy: accuracy)
        XCTAssertTrue(high.alerts.contains(.pumpRateTooHigh))
    }

    // MARK: Bolus

    func testAtropineBolus_1mg_from0_25mgPerMLAmpoule() {
        let (drug, regimen) = Fixtures.adultRegimen("sulfas-atropin", "bolus-bradikardia")
        let r = InfusionCalculator.bolus(drug: drug, regimen: regimen, doseMg: 1, ampoule: drug.ampoule)
        XCTAssertTrue(r.isValid)
        XCTAssertEqual(r.undilutedVolumeML, 4, accuracy: accuracy)
        XCTAssertEqual(r.ampoulesNeeded, 4, accuracy: accuracy)
        XCTAssertEqual(r.dosesUntilCumulativeMax, 3)
        XCTAssertTrue(r.alerts.contains(.cumulativeBolusLimit))
    }

    func testEpinephrineArrestBolus() {
        let (drug, regimen) = Fixtures.adultRegimen("epinefrin", "bolus-henti-jantung")
        let r = InfusionCalculator.bolus(drug: drug, regimen: regimen, doseMg: 1, ampoule: drug.ampoule)
        XCTAssertEqual(r.undilutedVolumeML, 1, accuracy: accuracy)
        XCTAssertNil(r.dosesUntilCumulativeMax)
    }

    func testAmiodaroneArrestBolus_aboveMaximumFlagged() {
        let (drug, regimen) = Fixtures.adultRegimen("amiodaron", "bolus-henti-jantung")
        let ok = InfusionCalculator.bolus(drug: drug, regimen: regimen, doseMg: 300, ampoule: drug.ampoule)
        XCTAssertEqual(ok.undilutedVolumeML, 6, accuracy: accuracy)
        let tooMuch = InfusionCalculator.bolus(drug: drug, regimen: regimen, doseMg: 450, ampoule: drug.ampoule)
        XCTAssertTrue(tooMuch.alerts.contains(.doseAboveMaximum))
    }

    func testBolusInvalidInputs() {
        let (drug, regimen) = Fixtures.adultRegimen("sulfas-atropin", "bolus-bradikardia")
        XCTAssertFalse(InfusionCalculator.bolus(drug: drug, regimen: regimen, doseMg: 0, ampoule: drug.ampoule).isValid)
        XCTAssertFalse(InfusionCalculator.bolus(drug: drug, regimen: regimen, doseMg: 1, ampoule: AmpouleStrength(mg: 0, mL: 1)).isValid)
    }
}

final class DripRateTests: XCTestCase {
    func testMacroAndMicroConversion() {
        XCTAssertEqual(DripRate.dropsPerMinute(mLPerHour: 60, set: .macro), 20, accuracy: accuracy)
        XCTAssertEqual(DripRate.dropsPerMinute(mLPerHour: 60, set: .micro), 60, accuracy: accuracy)
        XCTAssertEqual(DripRate.mLPerHour(dropsPerMinute: 20, set: .macro), 60, accuracy: accuracy)
        XCTAssertEqual(DripRate.mLPerHour(dropsPerMinute: 60, set: .micro), 60, accuracy: accuracy)
        // 500 mL in 4 hours → 125 mL/jam → 41,67 tpm makro
        let rate = DripRate.mLPerHour(volumeML: 500, overHours: 4)
        XCTAssertEqual(rate, 125, accuracy: accuracy)
        XCTAssertEqual(RateTriple(mLPerHour: rate).macroDropsPerMinute, 125.0 / 3, accuracy: accuracy)
    }

    func testInvalidRatesClampToZero() {
        XCTAssertEqual(DripRate.dropsPerMinute(mLPerHour: -5, set: .macro), 0)
        XCTAssertEqual(DripRate.dropsPerMinute(mLPerHour: .infinity, set: .macro), 0)
        XCTAssertEqual(DripRate.mLPerHour(volumeML: 100, overHours: 0), 0)
        XCTAssertEqual(RateTriple(mLPerHour: .nan).mLPerHour, 0)
    }
}
