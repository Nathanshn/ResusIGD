import Foundation
import SwiftData
import ClinicalCore

/// SwiftData mirror of the bundled clinical catalog.
/// The full monograph is stored as JSON (`payload`) so the pure `ClinicalCore` structs stay the single
/// source of truth for calculations, while SwiftData provides offline persistence, ordering and
/// per-hospital customisation (`isUserModified` records survive seed upgrades).
@Model
final class AdultDrugRecord {
    @Attribute(.unique) var drugID: String
    var name: String
    var sortIndex: Int
    var isUserModified: Bool
    var payload: Data

    init(drug: AdultDrug, sortIndex: Int, isUserModified: Bool = false) {
        self.drugID = drug.id
        self.name = drug.name
        self.sortIndex = sortIndex
        self.isUserModified = isUserModified
        self.payload = (try? JSONEncoder().encode(drug)) ?? Data()
    }

    var drug: AdultDrug? { try? JSONDecoder().decode(AdultDrug.self, from: payload) }
}

@Model
final class PediatricDrugRecord {
    @Attribute(.unique) var drugID: String
    var name: String
    var categoryRaw: String
    var sortIndex: Int
    var isUserModified: Bool
    var payload: Data

    init(drug: PediatricDrug, sortIndex: Int, isUserModified: Bool = false) {
        self.drugID = drug.id
        self.name = drug.name
        self.categoryRaw = drug.category.rawValue
        self.sortIndex = sortIndex
        self.isUserModified = isUserModified
        self.payload = (try? JSONEncoder().encode(drug)) ?? Data()
    }

    var drug: PediatricDrug? { try? JSONDecoder().decode(PediatricDrug.self, from: payload) }
}

@Model
final class GuidelineRecord {
    @Attribute(.unique) var guidelineID: String
    var title: String
    var categoryRaw: String
    var sortIndex: Int
    var isUserModified: Bool
    var payload: Data

    init(guideline: Guideline, sortIndex: Int, isUserModified: Bool = false) {
        self.guidelineID = guideline.id
        self.title = guideline.title
        self.categoryRaw = guideline.category.rawValue
        self.sortIndex = sortIndex
        self.isUserModified = isUserModified
        self.payload = (try? JSONEncoder().encode(guideline)) ?? Data()
    }

    var guideline: Guideline? { try? JSONDecoder().decode(Guideline.self, from: payload) }
}

/// A persisted Code Blue / Status Epilepticus session (survives app termination mid-resuscitation).
@Model
final class ResusSessionRecord {
    @Attribute(.unique) var sessionID: UUID
    var modeRaw: String
    var startedAt: Date
    var endedAt: Date?
    var patientInfo: String
    var payload: Data

    init(engine: ResusSessionEngine, patientInfo: String = "") {
        self.sessionID = UUID()
        self.modeRaw = engine.mode.rawValue
        self.startedAt = engine.startedAt
        self.endedAt = engine.endedAt
        self.patientInfo = patientInfo
        self.payload = (try? JSONEncoder().encode(engine)) ?? Data()
    }

    var engine: ResusSessionEngine? { try? JSONDecoder().decode(ResusSessionEngine.self, from: payload) }

    func update(with engine: ResusSessionEngine) {
        endedAt = engine.endedAt
        payload = (try? JSONEncoder().encode(engine)) ?? payload
    }
}
