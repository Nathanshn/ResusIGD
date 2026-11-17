import Foundation
import Observation
import SwiftData
import ClinicalCore

/// Imports the bundled seed into SwiftData (first launch / seed upgrade) and exposes decoded,
/// ready-to-calculate catalog arrays to the view models. Everything is local — no network.
@MainActor
@Observable
final class ClinicalLibrary {
    private(set) var adultDrugs: [AdultDrug] = []
    private(set) var pediatricDrugs: [PediatricDrug] = []
    private(set) var guidelines: [Guideline] = []
    private(set) var loadError: String?

    static let seedVersionKey = "clinicalSeedVersionSignature"

    func bootstrap(context: ModelContext) {
        do {
            let seed = try SeedRepository.loadBundled()
            try importIfNeeded(seed: seed, context: context)
            reload(context: context)
            if adultDrugs.isEmpty || pediatricDrugs.isEmpty || guidelines.isEmpty {
                // Defensive fallback: never leave the resuscitation room without data.
                adultDrugs = seed.adultDrugs
                pediatricDrugs = seed.pediatricDrugs
                guidelines = seed.guidelines
            }
        } catch {
            loadError = String(describing: error)
            reload(context: context)
        }
    }

    func reload(context: ModelContext) {
        let adult = (try? context.fetch(FetchDescriptor<AdultDrugRecord>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        let pediatric = (try? context.fetch(FetchDescriptor<PediatricDrugRecord>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        let guideline = (try? context.fetch(FetchDescriptor<GuidelineRecord>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        adultDrugs = adult.compactMap(\.drug)
        pediatricDrugs = pediatric.compactMap(\.drug)
        guidelines = guideline.compactMap(\.guideline)
    }

    /// Re-imports when the seed signature changes. Records flagged `isUserModified` are preserved.
    private func importIfNeeded(seed: ClinicalSeed, context: ModelContext) throws {
        let defaults = UserDefaults.standard
        let existingCount = (try? context.fetchCount(FetchDescriptor<AdultDrugRecord>())) ?? 0
        if defaults.string(forKey: Self.seedVersionKey) == seed.versionSignature && existingCount > 0 {
            return
        }

        let adultRecords = try context.fetch(FetchDescriptor<AdultDrugRecord>())
        let keptAdult = Set(adultRecords.filter(\.isUserModified).map(\.drugID))
        for record in adultRecords where !record.isUserModified { context.delete(record) }
        for (index, drug) in seed.adultDrugs.enumerated() where !keptAdult.contains(drug.id) {
            context.insert(AdultDrugRecord(drug: drug, sortIndex: index))
        }

        let pediatricRecords = try context.fetch(FetchDescriptor<PediatricDrugRecord>())
        let keptPediatric = Set(pediatricRecords.filter(\.isUserModified).map(\.drugID))
        for record in pediatricRecords where !record.isUserModified { context.delete(record) }
        for (index, drug) in seed.pediatricDrugs.enumerated() where !keptPediatric.contains(drug.id) {
            context.insert(PediatricDrugRecord(drug: drug, sortIndex: index))
        }

        let guidelineRecords = try context.fetch(FetchDescriptor<GuidelineRecord>())
        let keptGuidelines = Set(guidelineRecords.filter(\.isUserModified).map(\.guidelineID))
        for record in guidelineRecords where !record.isUserModified { context.delete(record) }
        for (index, guideline) in seed.guidelines.enumerated() where !keptGuidelines.contains(guideline.id) {
            context.insert(GuidelineRecord(guideline: guideline, sortIndex: index))
        }

        try context.save()
        defaults.set(seed.versionSignature, forKey: Self.seedVersionKey)
    }
}
