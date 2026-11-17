import XCTest
@testable import ClinicalCore

final class WeightEstimatorTests: XCTestCase {
    func testAPLS() {
        XCTAssertEqual(PediatricWeightEstimator.apls(ageMonths: 0)?.weightKg ?? 0, 4, accuracy: accuracy)
        XCTAssertEqual(PediatricWeightEstimator.apls(ageMonths: 6)?.weightKg ?? 0, 7, accuracy: accuracy)
        XCTAssertEqual(PediatricWeightEstimator.apls(ageMonths: 24)?.weightKg ?? 0, 12, accuracy: accuracy)
        XCTAssertEqual(PediatricWeightEstimator.apls(ageMonths: 60)?.weightKg ?? 0, 18, accuracy: accuracy)
        XCTAssertEqual(PediatricWeightEstimator.apls(ageMonths: 71)?.weightKg ?? 0, 18, accuracy: accuracy, "5 y 11 m uses completed years")
        XCTAssertEqual(PediatricWeightEstimator.apls(ageMonths: 72)?.weightKg ?? 0, 25, accuracy: accuracy)
        XCTAssertEqual(PediatricWeightEstimator.apls(ageMonths: 144)?.weightKg ?? 0, 43, accuracy: accuracy)
        XCTAssertEqual(PediatricWeightEstimator.apls(ageMonths: 144)?.outsideValidatedRange, false)
        XCTAssertEqual(PediatricWeightEstimator.apls(ageMonths: 168)?.outsideValidatedRange, true)
        XCTAssertNil(PediatricWeightEstimator.apls(ageMonths: -1))
    }

    func testLuscombeOwens() {
        XCTAssertEqual(PediatricWeightEstimator.luscombeOwens(ageMonths: 48)?.weightKg ?? 0, 19, accuracy: accuracy)
        XCTAssertEqual(PediatricWeightEstimator.luscombeOwens(ageMonths: 6)?.outsideValidatedRange, true)
    }

    func testLengthZones() {
        XCTAssertEqual(PediatricWeightEstimator.lengthZone(lengthCm: 80)?.zone?.colorKey, "purple")
        XCTAssertEqual(PediatricWeightEstimator.lengthZone(lengthCm: 80)?.weightKg ?? 0, 10.5, accuracy: accuracy)
        XCTAssertEqual(PediatricWeightEstimator.lengthZone(lengthCm: 100)?.zone?.colorKey, "white")
        XCTAssertEqual(PediatricWeightEstimator.lengthZone(lengthCm: 59.5)?.zone?.colorKey, "pink", "lower bound inclusive")
        XCTAssertEqual(PediatricWeightEstimator.lengthZone(lengthCm: 149.9)?.zone?.colorKey, "green")
        let outside = PediatricWeightEstimator.lengthZone(lengthCm: 40)
        XCTAssertNil(outside?.zone)
        XCTAssertEqual(outside?.outsideValidatedRange, true)
    }

    func testZonesAreContiguous() {
        let zones = PediatricWeightEstimator.lengthZones
        for (a, b) in zip(zones, zones.dropFirst()) {
            XCTAssertEqual(a.maxLengthCm, b.minLengthCm, accuracy: accuracy)
            XCTAssertLessThan(a.maxWeightKg, b.minWeightKg)
        }
    }

    func testTraubJohnson() {
        XCTAssertEqual(PediatricWeightEstimator.traubJohnson(lengthCm: 100)?.weightKg ?? 0, 2.05 * exp(2.0), accuracy: accuracy)
    }

    func testBestEstimatePrefersLength() {
        XCTAssertEqual(PediatricWeightEstimator.bestEstimate(lengthCm: 100, ageMonths: 24)?.method, .lengthZone)
        XCTAssertEqual(PediatricWeightEstimator.bestEstimate(lengthCm: nil, ageMonths: 24)?.method, .apls)
        XCTAssertNil(PediatricWeightEstimator.bestEstimate(lengthCm: nil, ageMonths: nil))
    }

    func testEquivalentAge() {
        XCTAssertEqual(PediatricWeightEstimator.equivalentAgeMonths(forWeightKg: 7), 6, accuracy: accuracy)
        XCTAssertEqual(PediatricWeightEstimator.equivalentAgeMonths(forWeightKg: 12), 24, accuracy: accuracy)
        XCTAssertEqual(PediatricWeightEstimator.equivalentAgeMonths(forWeightKg: 25), 72, accuracy: accuracy)
    }
}

final class ResuscitationEquipmentTests: XCTestCase {
    func testFourYearOld16kg() throws {
        let e = try XCTUnwrap(ResuscitationEquipment.calculate(weightKg: 16, ageMonths: 48))
        XCTAssertEqual(e.ettUncuffedID, 5.0)
        XCTAssertEqual(e.ettCuffedID, 4.5)
        XCTAssertEqual(e.ettDepthCm, 14)
        XCTAssertEqual(e.lmaSize, 2)
        XCTAssertEqual(e.defibrillationFirstJ, 32)
        XCTAssertEqual(e.defibrillationSubsequentJ, 64)
        XCTAssertEqual(e.cardioversionLowJ, 8)
        XCTAssertEqual(e.cardioversionHighJ, 16)
        XCTAssertEqual(e.epinephrineArrestMg, 0.16, accuracy: accuracy)
        XCTAssertEqual(e.epinephrineArrestML, 1.6, accuracy: accuracy)
        XCTAssertFalse(e.ageDerivedFromWeight)
    }

    func testTubeSizesRoundHalfDown() throws {
        let two = try XCTUnwrap(ResuscitationEquipment.calculate(weightKg: 12, ageMonths: 24))
        XCTAssertEqual(two.ettUncuffedID, 4.5)
        XCTAssertEqual(two.ettCuffedID, 4.0)
        XCTAssertEqual(two.ettDepthCm, 13)
        let three = try XCTUnwrap(ResuscitationEquipment.calculate(weightKg: 14, ageMonths: 36))
        XCTAssertEqual(three.ettUncuffedID, 4.5, "4,75 → 4,5 (ties down)")
        XCTAssertEqual(three.ettCuffedID, 4.0, "4,25 → 4,0")
        let eight = try XCTUnwrap(ResuscitationEquipment.calculate(weightKg: 31, ageMonths: 96))
        XCTAssertEqual(eight.ettUncuffedID, 6.0)
        XCTAssertEqual(eight.ettCuffedID, 5.5)
        XCTAssertEqual(eight.ettDepthCm, 16)
    }

    func testInfantAndNeonate() throws {
        let infant = try XCTUnwrap(ResuscitationEquipment.calculate(weightKg: 6, ageMonths: 3))
        XCTAssertEqual(infant.ettUncuffedID, 3.5)
        XCTAssertEqual(infant.ettCuffedID, 3.0)
        XCTAssertEqual(infant.ettDepthCm, 10.5)
        XCTAssertEqual(infant.lmaSize, 1.5)
        let neonate = try XCTUnwrap(ResuscitationEquipment.calculate(weightKg: 3, ageMonths: 0.5))
        XCTAssertEqual(neonate.ettUncuffedID, 3.5)
        XCTAssertEqual(neonate.ettDepthCm, 9)
        XCTAssertTrue(neonate.laryngoscope.contains("Miller"))
    }

    func testEnergyAndEpinephrineCaps() throws {
        let big = try XCTUnwrap(ResuscitationEquipment.calculate(weightKg: 60, ageMonths: 168))
        XCTAssertEqual(big.defibrillationSubsequentJ, 200, "4 J/kg × 60 = 240 → capped at adult 200 J")
        XCTAssertEqual(big.defibrillationFirstJ, 120)
        let huge = try XCTUnwrap(ResuscitationEquipment.calculate(weightKg: 120, ageMonths: nil))
        XCTAssertEqual(huge.epinephrineArrestMg, 1, accuracy: accuracy)
    }

    func testWeightOnly_derivesAge() throws {
        let e = try XCTUnwrap(ResuscitationEquipment.calculate(weightKg: 12, ageMonths: nil))
        XCTAssertTrue(e.ageDerivedFromWeight)
        XCTAssertEqual(e.ageMonthsUsed, 24, accuracy: accuracy)
        XCTAssertEqual(e.ettUncuffedID, 4.5)
    }

    func testInvalidWeight() {
        XCTAssertNil(ResuscitationEquipment.calculate(weightKg: 0, ageMonths: 12))
        XCTAssertNil(ResuscitationEquipment.calculate(weightKg: .nan, ageMonths: 12))
    }
}

final class FluidCalculatorTests: XCTestCase {
    func testBolus20mLPerKg() throws {
        let bolus = try XCTUnwrap(FluidCalculator.bolus(weightKg: 15))
        XCTAssertEqual(bolus.volumeML, 300, accuracy: accuracy)
        XCTAssertFalse(bolus.cappedAtAdultVolume)
        let adult = try XCTUnwrap(FluidCalculator.bolus(weightKg: 70))
        XCTAssertEqual(adult.volumeML, 1000, accuracy: accuracy)
        XCTAssertTrue(adult.cappedAtAdultVolume)
        XCTAssertTrue(adult.alerts.contains(.fluidCappedAtAdultVolume))
        XCTAssertEqual(try XCTUnwrap(FluidCalculator.bolus(weightKg: 50)).volumeML, 1000, accuracy: accuracy, "exactly at cap")
        XCTAssertNil(FluidCalculator.bolus(weightKg: 0))
    }

    func testHollidaySegar() throws {
        let eight = try XCTUnwrap(FluidCalculator.hollidaySegar(weightKg: 8))
        XCTAssertEqual(eight.hourlyML, 32, accuracy: accuracy)
        XCTAssertEqual(eight.dailyML, 800, accuracy: accuracy)

        let ten = try XCTUnwrap(FluidCalculator.hollidaySegar(weightKg: 10))
        XCTAssertEqual(ten.hourlyML, 40, accuracy: accuracy)
        XCTAssertEqual(ten.dailyML, 1000, accuracy: accuracy)

        let fifteen = try XCTUnwrap(FluidCalculator.hollidaySegar(weightKg: 15))
        XCTAssertEqual(fifteen.hourlyML, 50, accuracy: accuracy)
        XCTAssertEqual(fifteen.dailyML, 1250, accuracy: accuracy)
        XCTAssertEqual(fifteen.rate.macroDropsPerMinute, 50.0 / 3, accuracy: accuracy)

        let twenty = try XCTUnwrap(FluidCalculator.hollidaySegar(weightKg: 20))
        XCTAssertEqual(twenty.hourlyML, 60, accuracy: accuracy)
        XCTAssertEqual(twenty.dailyML, 1500, accuracy: accuracy)

        let twentyFive = try XCTUnwrap(FluidCalculator.hollidaySegar(weightKg: 25))
        XCTAssertEqual(twentyFive.hourlyML, 65, accuracy: accuracy)
        XCTAssertEqual(twentyFive.dailyML, 1600, accuracy: accuracy)
    }

    func testHollidaySegarCappedForLargePatients() throws {
        let adult = try XCTUnwrap(FluidCalculator.hollidaySegar(weightKg: 70))
        XCTAssertEqual(adult.hourlyML, 100, accuracy: accuracy)
        XCTAssertEqual(adult.dailyML, 2400, accuracy: accuracy)
        XCTAssertTrue(adult.hourlyCapped && adult.dailyCapped)
        XCTAssertTrue(adult.alerts.contains(.maintenanceCappedAtAdultRate))
        XCTAssertNil(FluidCalculator.hollidaySegar(weightKg: -3))
    }
}
