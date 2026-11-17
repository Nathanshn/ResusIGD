import XCTest
import SwiftData
import ClinicalCore
@testable import ResusIGD

/// App-level tests: SwiftData seed import and view-model wiring (pure math is covered in ClinicalCore).
@MainActor
final class ResusIGDTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([AdultDrugRecord.self, PediatricDrugRecord.self, GuidelineRecord.self, ResusSessionRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func resetSeedVersion() {
        UserDefaults.standard.removeObject(forKey: ClinicalLibrary.seedVersionKey)
    }

    func testSeedImportsIntoSwiftData() throws {
        resetSeedVersion()
        let context = try makeContext()
        let library = ClinicalLibrary()
        library.bootstrap(context: context)
        XCTAssertNil(library.loadError)
        XCTAssertEqual(library.adultDrugs.first?.id, "norepinefrin", "seed order preserved")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdultDrugRecord>()), library.adultDrugs.count)
        XCTAssertGreaterThanOrEqual(library.pediatricDrugs.count, 19)
        XCTAssertGreaterThanOrEqual(library.guidelines.count, 10)
    }

    func testUserModifiedRecordsSurviveReimport() throws {
        resetSeedVersion()
        let context = try makeContext()
        let library = ClinicalLibrary()
        library.bootstrap(context: context)

        let record = try XCTUnwrap(context.fetch(FetchDescriptor<AdultDrugRecord>()).first { $0.drugID == "dopamin" })
        var custom = try XCTUnwrap(record.drug)
        custom.ampoule = AmpouleStrength(mg: 200, mL: 10)
        context.delete(record)
        context.insert(AdultDrugRecord(drug: custom, sortIndex: 1, isUserModified: true))
        try context.save()

        UserDefaults.standard.set("old-version", forKey: ClinicalLibrary.seedVersionKey)
        library.bootstrap(context: context)
        XCTAssertEqual(library.adultDrugs.first { $0.id == "dopamin" }?.ampoule.mL, 10)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AdultDrugRecord>()), library.adultDrugs.count, "no duplicates")
    }

    func testTitrationViewModelDefaultsAndResult() throws {
        let seed = try SeedRepository.loadBundled()
        let model = TitrationViewModel()
        model.load(drugs: seed.adultDrugs)
        model.weightText = "70"
        model.dose = 0.1
        XCTAssertEqual(model.drug?.id, "norepinefrin")
        let result = try XCTUnwrap(model.infusionResult)
        XCTAssertEqual(result.rateMLPerHour, 5.25, accuracy: 1e-6)

        model.selectDrug("sulfas-atropin")
        XCTAssertTrue(model.isBolus)
        XCTAssertEqual(model.bolusResult?.undilutedVolumeML ?? 0, 4, accuracy: 1e-6)
    }

    func testPediatricViewModelEstimationMode() throws {
        let model = PediatricViewModel()
        model.estimationMode = true
        model.estimationMethod = .lengthZone
        XCTAssertNotNil(model.estimationNeedsInput)
        model.lengthText = "80"
        XCTAssertEqual(model.weightKg ?? 0, 10.5, accuracy: 1e-6)
        XCTAssertNotNil(model.equipment)
        model.estimationMode = false
        model.weightText = "120"
        model.ageYearsText = "2"
        XCTAssertEqual(model.patientAlerts.first?.level, .danger)
    }

    func testCodeTimerPersistsAndRestoresActiveSession() throws {
        let context = try makeContext()
        let first = CodeTimerViewModel()
        first.attach(context: context)
        first.start()
        first.log(ResusQuickAction(label: "Epinefrin 1 mg IV", kind: .epinephrine, systemImage: "syringe.fill"))

        let second = CodeTimerViewModel()
        second.attach(context: context)
        XCTAssertTrue(second.isActive, "unfinished session restored after relaunch")
        XCTAssertEqual(second.session?.count(of: .epinephrine), 1)
        second.end()
        XCTAssertFalse(second.isActive)
        XCTAssertTrue(second.soapText().contains("Epinefrin: 1×"))
    }
}
