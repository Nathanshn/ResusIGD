import XCTest
@testable import ClinicalCore

final class BurnCalculatorTests: XCTestCase {
    private func allRegions() -> [BurnRegion: Double] {
        Dictionary(uniqueKeysWithValues: BurnRegion.allCases.map { ($0, 1.0) })
    }

    func testRuleOfNines_totalsAlways100() {
        for age in [0.0, 1, 3, 5, 9, 10, 30, 80] {
            XCTAssertEqual(RuleOfNines.totalBSA(fractions: allRegions(), ageYears: age), 100, accuracy: accuracy, "age \(age)")
        }
        XCTAssertEqual(RuleOfNines.totalBSA(fractions: allRegions(), ageYears: nil), 100, accuracy: accuracy)
    }

    func testRuleOfNines_adultAndChildRegions() {
        XCTAssertEqual(RuleOfNines.totalBSA(fractions: [.anteriorTrunk: 1, .rightArm: 1], ageYears: 40), 27, accuracy: accuracy)
        XCTAssertEqual(RuleOfNines.percentage(of: .headNeck, ageYears: 0.5), 18)
        XCTAssertEqual(RuleOfNines.percentage(of: .rightLeg, ageYears: 0.5), 13.5)
        XCTAssertEqual(RuleOfNines.percentage(of: .headNeck, ageYears: 5), 14)
        XCTAssertEqual(RuleOfNines.percentage(of: .rightLeg, ageYears: 5), 15.5)
        XCTAssertEqual(RuleOfNines.percentage(of: .headNeck, ageYears: 40), 9)
        XCTAssertEqual(RuleOfNines.percentage(of: .leftLeg, ageYears: 40), 18)
    }

    func testRuleOfNines_partialFractionsAndClamping() {
        XCTAssertEqual(RuleOfNines.totalBSA(fractions: [.posteriorTrunk: 0.5], ageYears: 40), 9, accuracy: accuracy)
        XCTAssertEqual(RuleOfNines.totalBSA(fractions: [.rightArm: 2.0, .leftArm: -1], ageYears: 40), 9, accuracy: accuracy)
    }

    func testParkland_70kg_30percent_2hoursAfterBurn() throws {
        let plan = try XCTUnwrap(ParklandCalculator.plan(weightKg: 70, tbsaPercent: 30, hoursSinceBurn: 2))
        XCTAssertEqual(plan.totalML, 8400, accuracy: accuracy)
        XCTAssertEqual(plan.firstHalfML, 4200, accuracy: accuracy)
        XCTAssertEqual(plan.remainingFirstPeriodHours, 6, accuracy: accuracy)
        XCTAssertEqual(plan.firstPeriodRate.mLPerHour, 700, accuracy: accuracy)        // 4200 ÷ 6 jam
        XCTAssertEqual(plan.firstPeriodRate.macroDropsPerMinute, 700.0 / 3, accuracy: accuracy)
        XCTAssertEqual(plan.secondPeriodRate.mLPerHour, 262.5, accuracy: accuracy)     // 4200 ÷ 16 jam
        XCTAssertEqual(plan.urineOutputTargetML.lowerBound, 35, accuracy: accuracy)
        XCTAssertTrue(plan.alerts.isEmpty)
    }

    func testParkland_atTimeZero_usesFull8Hours() throws {
        let plan = try XCTUnwrap(ParklandCalculator.plan(weightKg: 70, tbsaPercent: 30, hoursSinceBurn: 0))
        XCTAssertEqual(plan.firstPeriodRate.mLPerHour, 525, accuracy: accuracy)
    }

    func testParkland_subtractsPrehospitalFluid() throws {
        let plan = try XCTUnwrap(ParklandCalculator.plan(weightKg: 70, tbsaPercent: 30, hoursSinceBurn: 2, alreadyGivenML: 1000))
        XCTAssertEqual(plan.firstPeriodRate.mLPerHour, 3200.0 / 6, accuracy: accuracy)
    }

    func testParkland_after8Hours_redistributesOutstandingVolume() throws {
        let plan = try XCTUnwrap(ParklandCalculator.plan(weightKg: 70, tbsaPercent: 30, hoursSinceBurn: 10))
        XCTAssertEqual(plan.firstPeriodRate.mLPerHour, 0)
        XCTAssertEqual(plan.secondPeriodRate.mLPerHour, 600, accuracy: accuracy)      // 8400 ÷ 14 jam
        XCTAssertTrue(plan.alerts.contains(.burnWindowElapsed))
    }

    func testParkland_formulasAndThresholds() throws {
        let atls = try XCTUnwrap(ParklandCalculator.plan(weightKg: 70, tbsaPercent: 30, hoursSinceBurn: 0, formula: .atlsAdult2))
        XCTAssertEqual(atls.totalML, 4200, accuracy: accuracy)
        let child = try XCTUnwrap(ParklandCalculator.plan(weightKg: 20, tbsaPercent: 15, hoursSinceBurn: 1, formula: .atlsChild3, isChild: true))
        XCTAssertEqual(child.totalML, 900, accuracy: accuracy)
        XCTAssertEqual(child.urineOutputTargetML.lowerBound, 20, accuracy: accuracy)   // 1 mL/kg/jam
        XCTAssertFalse(child.alerts.contains(.burnBelowFormalResuscitationThreshold))
        let small = try XCTUnwrap(ParklandCalculator.plan(weightKg: 70, tbsaPercent: 15, hoursSinceBurn: 1))
        XCTAssertTrue(small.alerts.contains(.burnBelowFormalResuscitationThreshold))
        XCTAssertNil(ParklandCalculator.plan(weightKg: 70, tbsaPercent: 0, hoursSinceBurn: 1))
        XCTAssertNil(ParklandCalculator.plan(weightKg: 70, tbsaPercent: 120, hoursSinceBurn: 1))
        XCTAssertNil(ParklandCalculator.plan(weightKg: 70, tbsaPercent: 30, hoursSinceBurn: -1))
    }
}

final class ScoreCalculatorTests: XCTestCase {
    func testGCS() throws {
        let normal = try XCTUnwrap(GCSCalculator.calculate(eye: 4, verbal: 5, motor: 6))
        XCTAssertEqual(normal.total, 15)
        XCTAssertEqual(normal.severityLevel, .info)
        let worst = try XCTUnwrap(GCSCalculator.calculate(eye: 1, verbal: 1, motor: 1))
        XCTAssertEqual(worst.total, 3)
        XCTAssertEqual(worst.severityLevel, .danger)
        let moderate = try XCTUnwrap(GCSCalculator.calculate(eye: 3, verbal: 4, motor: 5))
        XCTAssertEqual(moderate.severityLevel, .warning)
        let boundary = try XCTUnwrap(GCSCalculator.calculate(eye: 2, verbal: 2, motor: 4))
        XCTAssertEqual(boundary.total, 8)
        XCTAssertEqual(boundary.severityLevel, .danger)
        let intubated = try XCTUnwrap(GCSCalculator.calculate(eye: 2, verbal: nil, motor: 4))
        XCTAssertEqual(intubated.notation, "E2VT M4 = 6T")
        XCTAssertNil(GCSCalculator.calculate(eye: 5, verbal: 5, motor: 6))
        XCTAssertNil(GCSCalculator.calculate(eye: 4, verbal: 6, motor: 6))
        XCTAssertEqual(GCSCalculator.items(for: .pediatric).count, 3)
    }

    func testNIHSS() {
        let zero = NIHSSCalculator.calculate(selections: Dictionary(uniqueKeysWithValues: NIHSSCalculator.items.map { ($0.id, $0.options[0]) }))
        XCTAssertEqual(zero.total, 0)
        XCTAssertTrue(zero.isComplete)

        let worstSelections = Dictionary(uniqueKeysWithValues: NIHSSCalculator.items.map { item in
            (item.id, item.options.filter { !$0.isUntestable }.max { $0.score < $1.score }!)
        })
        XCTAssertEqual(NIHSSCalculator.calculate(selections: worstSelections).total, NIHSSCalculator.maxScore)
        XCTAssertEqual(NIHSSCalculator.items.count, 15)

        let untestable = NIHSSCalculator.calculate(selections: ["5a": ScoreOption(0, "UN", untestable: true)])
        XCTAssertEqual(untestable.total, 0)
        XCTAssertFalse(untestable.isComplete)
        XCTAssertEqual(NIHSSCalculator.severity(for: 4), "Stroke ringan (1–4)")
        XCTAssertEqual(NIHSSCalculator.severity(for: 16), "Stroke sedang–berat (16–20)")
    }
}

final class ElectrolyteCalculatorTests: XCTestCase {
    func testTBWFactors() {
        XCTAssertEqual(ElectrolyteCalculator.tbwFactor(ageYears: 10, sex: .female), 0.6)
        XCTAssertEqual(ElectrolyteCalculator.tbwFactor(ageYears: 40, sex: .male), 0.6)
        XCTAssertEqual(ElectrolyteCalculator.tbwFactor(ageYears: 40, sex: .female), 0.5)
        XCTAssertEqual(ElectrolyteCalculator.tbwFactor(ageYears: 70, sex: .male), 0.5)
        XCTAssertEqual(ElectrolyteCalculator.tbwFactor(ageYears: 70, sex: .female), 0.45)
    }

    func testHyponatremia_AdrogueMadias() throws {
        let plan = try XCTUnwrap(ElectrolyteCalculator.sodiumCorrection(currentSodium: 115, weightKg: 70, ageYears: 40, sex: .male))
        XCTAssertEqual(plan.totalBodyWaterL, 42, accuracy: accuracy)
        XCTAssertEqual(plan.targetSodium, 123, accuracy: accuracy)
        XCTAssertEqual(plan.deficitMmol, 336, accuracy: accuracy)
        XCTAssertEqual(plan.changePerLiter, 398.0 / 43, accuracy: accuracy)
        XCTAssertEqual(plan.volumeML, 8 / (398.0 / 43) * 1000, accuracy: 1e-3)
        XCTAssertEqual(plan.rate.mLPerHour, plan.volumeML / 24, accuracy: accuracy)
        XCTAssertTrue(plan.alerts.contains(.sodiumSevere))
        XCTAssertTrue(plan.alerts.contains(.correctionLimit))
    }

    func testHyponatremia_targetNeverAbove135() throws {
        let plan = try XCTUnwrap(ElectrolyteCalculator.sodiumCorrection(currentSodium: 131, weightKg: 70, ageYears: 40, sex: .male, maxRisePer24h: 10))
        XCTAssertEqual(plan.targetSodium, 135, accuracy: accuracy)
        XCTAssertFalse(plan.alerts.contains(.sodiumSevere))
    }

    func testNormalSodium_noCorrection() throws {
        let plan = try XCTUnwrap(ElectrolyteCalculator.sodiumCorrection(currentSodium: 138, weightKg: 70, ageYears: 40, sex: .male))
        XCTAssertEqual(plan.volumeML, 0)
        XCTAssertTrue(plan.alerts.contains(.sodiumNotLow))
        XCTAssertNil(ElectrolyteCalculator.sodiumCorrection(currentSodium: 50, weightKg: 70, ageYears: 40, sex: .male))
        XCTAssertNil(ElectrolyteCalculator.sodiumCorrection(currentSodium: 120, weightKg: 0, ageYears: 40, sex: .male))
    }

    func testInfusateBelowSerumSodium_isFlagged() throws {
        // RL (130) cannot raise a serum Na of 132
        let plan = try XCTUnwrap(ElectrolyteCalculator.sodiumCorrection(currentSodium: 132, weightKg: 70, ageYears: 40, sex: .male, infusate: .ringerLactate))
        XCTAssertFalse(plan.changePerLiter > 0)
        XCTAssertEqual(plan.volumeML, 0)
        XCTAssertTrue(plan.alerts.contains(.invalidInput))
    }

    func testNearIsotonicInfusate_flagsImpracticalVolume() throws {
        // RL for Na 125 would need ≈ 68,8 L in 24 h — must be refused as unrealistic
        let plan = try XCTUnwrap(ElectrolyteCalculator.sodiumCorrection(currentSodium: 125, weightKg: 70, ageYears: 40, sex: .male, infusate: .ringerLactate))
        XCTAssertEqual(plan.volumeML, 68_800, accuracy: 1e-3)
        XCTAssertEqual(plan.alerts.first { $0.code == .impracticalVolume }?.level, .danger)
        let hypertonic = try XCTUnwrap(ElectrolyteCalculator.sodiumCorrection(currentSodium: 125, weightKg: 70, ageYears: 40, sex: .male))
        XCTAssertFalse(hypertonic.alerts.contains(.impracticalVolume))
    }

    func testPotassiumDrip_peripheralWithinLimits() throws {
        let plan = try XCTUnwrap(ElectrolyteCalculator.potassiumDrip(currentPotassium: 2.9, totalMEq: 20, volumeML: 500, rateMEqPerHour: 10, access: .peripheral, weightKg: 70, isChild: false))
        XCTAssertEqual(plan.concentrationMEqPerL, 40, accuracy: accuracy)
        XCTAssertEqual(plan.rate.mLPerHour, 250, accuracy: accuracy)
        XCTAssertEqual(plan.durationHours, 2, accuracy: accuracy)
        XCTAssertEqual(plan.expectedRise, 0.2, accuracy: accuracy)
        XCTAssertTrue(plan.alerts.isEmpty)
    }

    func testPotassiumDrip_guardrails() throws {
        let concentrated = try XCTUnwrap(ElectrolyteCalculator.potassiumDrip(currentPotassium: 2.9, totalMEq: 40, volumeML: 500, rateMEqPerHour: 10, access: .peripheral, weightKg: 70, isChild: false))
        XCTAssertTrue(concentrated.alerts.contains(.potassiumConcentrationExceeded))
        let fast = try XCTUnwrap(ElectrolyteCalculator.potassiumDrip(currentPotassium: 2.9, totalMEq: 20, volumeML: 500, rateMEqPerHour: 20, access: .peripheral, weightKg: 70, isChild: false))
        XCTAssertEqual(fast.alerts.first { $0.code == .potassiumRateExceeded }?.level, .danger)
        let centralFast = try XCTUnwrap(ElectrolyteCalculator.potassiumDrip(currentPotassium: 2.4, totalMEq: 40, volumeML: 250, rateMEqPerHour: 20, access: .central, weightKg: 70, isChild: false))
        XCTAssertEqual(centralFast.alerts.first { $0.code == .potassiumRateExceeded }?.level, .warning)
        let child = try XCTUnwrap(ElectrolyteCalculator.potassiumDrip(currentPotassium: 2.9, totalMEq: 10, volumeML: 250, rateMEqPerHour: 10, access: .peripheral, weightKg: 10, isChild: true))
        XCTAssertEqual(child.maxRateMEqPerHour, 5, accuracy: accuracy)
        XCTAssertEqual(child.alerts.first { $0.code == .potassiumRateExceeded }?.level, .danger)
        let normalK = try XCTUnwrap(ElectrolyteCalculator.potassiumDrip(currentPotassium: 4.0, totalMEq: 20, volumeML: 500, rateMEqPerHour: 10, access: .peripheral, weightKg: 70, isChild: false))
        XCTAssertTrue(normalK.alerts.contains(.potassiumNotLow))
        XCTAssertNil(ElectrolyteCalculator.potassiumDrip(currentPotassium: 3, totalMEq: 0, volumeML: 500, rateMEqPerHour: 10, access: .peripheral, weightKg: 70, isChild: false))
    }

    func testAlteplase() throws {
        let plan = try XCTUnwrap(ElectrolyteCalculator.alteplase(weightKg: 70))
        XCTAssertEqual(plan.totalMg, 63, accuracy: accuracy)
        XCTAssertEqual(plan.bolusMg, 6.3, accuracy: accuracy)
        XCTAssertEqual(plan.infusionMg, 56.7, accuracy: accuracy)
        XCTAssertEqual(plan.infusionRateMLPerHour, 56.7, accuracy: accuracy)
        XCTAssertFalse(plan.wasCapped)
        let heavy = try XCTUnwrap(ElectrolyteCalculator.alteplase(weightKg: 110))
        XCTAssertEqual(heavy.totalMg, 90, accuracy: accuracy)
        XCTAssertEqual(heavy.bolusMg, 9, accuracy: accuracy)
        XCTAssertTrue(heavy.alerts.contains(.alteplaseCapped))
        XCTAssertEqual(try XCTUnwrap(ElectrolyteCalculator.alteplase(weightKg: 100)).totalMg, 90, accuracy: accuracy)
        XCTAssertFalse(try XCTUnwrap(ElectrolyteCalculator.alteplase(weightKg: 100)).wasCapped, "exactly 90 mg is not capped")
    }
}
