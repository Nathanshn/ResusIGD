import Foundation

/// Envelope used by every seed JSON file.
public struct SeedFile<Item: Codable & Sendable>: Codable, Sendable {
    public var version: Int
    public var items: [Item]
}

/// All bundled offline clinical content.
public struct ClinicalSeed: Sendable {
    public let adultDrugs: [AdultDrug]
    public let pediatricDrugs: [PediatricDrug]
    public let guidelines: [Guideline]
    /// Changes whenever any seed file version changes; the app re-imports when it differs.
    public let versionSignature: String
}

public enum SeedError: Error, CustomStringConvertible {
    case missingResource(String)
    case decoding(String, Error)

    public var description: String {
        switch self {
        case .missingResource(let name): "Seed file tidak ditemukan: \(name).json"
        case .decoding(let name, let error): "Gagal membaca \(name).json: \(error)"
        }
    }
}

public enum SeedRepository {
    public static let adultDrugsFile = "adult_drugs"
    public static let pediatricDrugsFile = "pediatric_drugs"
    public static let guidelinesFile = "guidelines"

    public static func loadBundled() throws -> ClinicalSeed {
        let adult: SeedFile<AdultDrug> = try load(adultDrugsFile)
        let pediatric: SeedFile<PediatricDrug> = try load(pediatricDrugsFile)
        let guidelines: SeedFile<Guideline> = try load(guidelinesFile)
        return ClinicalSeed(
            adultDrugs: adult.items,
            pediatricDrugs: pediatric.items,
            guidelines: guidelines.items,
            versionSignature: "a\(adult.version)-p\(pediatric.version)-g\(guidelines.version)"
        )
    }

    public static func load<Item: Codable & Sendable>(_ name: String, bundle: Bundle? = nil) throws -> SeedFile<Item> {
        let bundle = bundle ?? Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "SeedData")
                ?? bundle.url(forResource: name, withExtension: "json") else {
            throw SeedError.missingResource(name)
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SeedFile<Item>.self, from: data)
        } catch {
            throw SeedError.decoding(name, error)
        }
    }
}

/// Consistency checks for the local drug database. Run in unit tests and after editing seed JSON.
public enum SeedValidator {
    public static func validate(_ seed: ClinicalSeed) -> [String] {
        validateAdult(seed.adultDrugs) + validatePediatric(seed.pediatricDrugs) + validateGuidelines(seed.guidelines)
    }

    public static func validateAdult(_ drugs: [AdultDrug]) -> [String] {
        var problems: [String] = []
        problems += duplicates(drugs.map(\.id), context: "adult drug id")
        for drug in drugs {
            let p = "[\(drug.id)]"
            if !(drug.ampoule.mg > 0 && drug.ampoule.mL > 0) { problems.append("\(p) ampoule strength must be > 0") }
            if !(drug.defaultAmpouleCount > 0) { problems.append("\(p) defaultAmpouleCount must be > 0") }
            if drug.regimens.isEmpty { problems.append("\(p) has no regimens") }
            for diluent in Diluent.allCases where drug.rule(for: diluent) == nil {
                problems.append("\(p) missing diluent rule for \(diluent.rawValue)")
            }
            if drug.hasInfusionRegimen && drug.ampoule.mL * drug.defaultAmpouleCount > drug.defaultFinalVolumeML {
                problems.append("\(p) default drug volume exceeds default final volume")
            }
            problems += duplicates(drug.regimens.map(\.id), context: "\(p) regimen id")
            for regimen in drug.regimens {
                let r = "\(p)[\(regimen.id)]"
                if regimen.mode == .infusion && regimen.unit == nil { problems.append("\(r) infusion regimen needs unit") }
                if !(regimen.minDose > 0 && regimen.minDose <= regimen.defaultDose && regimen.defaultDose <= regimen.maxDose) {
                    problems.append("\(r) requires 0 < min ≤ default ≤ max")
                }
                if !(regimen.step > 0) { problems.append("\(r) step must be > 0") }
                if let ceiling = regimen.hardCeilingDose, ceiling < regimen.maxDose {
                    problems.append("\(r) hardCeilingDose below maxDose")
                }
            }
        }
        return problems
    }

    public static func validatePediatric(_ drugs: [PediatricDrug]) -> [String] {
        var problems: [String] = []
        problems += duplicates(drugs.map(\.id), context: "pediatric drug id")
        for drug in drugs {
            let p = "[\(drug.id)]"
            problems += duplicates(drug.formulations.map(\.id), context: "\(p) formulation id")
            problems += duplicates(drug.regimens.map(\.id), context: "\(p) regimen id")
            for formulation in drug.formulations {
                switch formulation.kind {
                case .liquid where !((formulation.mgPerML ?? 0) > 0):
                    problems.append("\(p)[\(formulation.id)] liquid needs mgPerML > 0")
                case .unit where !((formulation.mgPerUnit ?? 0) > 0):
                    problems.append("\(p)[\(formulation.id)] unit needs mgPerUnit > 0")
                default: break
                }
            }
            for regimen in drug.regimens {
                let r = "\(p)[\(regimen.id)]"
                if regimen.formulationIDs.isEmpty { problems.append("\(r) has no formulations") }
                for id in regimen.formulationIDs where !drug.formulations.contains(where: { $0.id == id }) {
                    problems.append("\(r) references unknown formulation \(id)")
                }
                if regimen.isWeightBanded {
                    let bands = regimen.fixedDoseBands ?? []
                    if bands.contains(where: { !($0.doseMg > 0) }) { problems.append("\(r) band dose must be > 0") }
                } else {
                    guard let min = regimen.mgPerKgMin, let def = regimen.mgPerKgDefault, let max = regimen.mgPerKgMax else {
                        problems.append("\(r) needs mgPerKgMin/Default/Max or fixedDoseBands")
                        continue
                    }
                    if !(min > 0 && min <= def && def <= max) { problems.append("\(r) requires 0 < min ≤ default ≤ max") }
                    if regimen.maxSingleDoseMg == nil { problems.append("\(r) weight-based regimen lacks maxSingleDoseMg (adult cap)") }
                }
            }
        }
        return problems
    }

    public static func validateGuidelines(_ guidelines: [Guideline]) -> [String] {
        var problems = duplicates(guidelines.map(\.id), context: "guideline id")
        for guideline in guidelines {
            if guideline.sections.isEmpty { problems.append("[\(guideline.id)] has no sections") }
            problems += duplicates(guideline.sections.map(\.id), context: "[\(guideline.id)] section id")
            for section in guideline.sections where section.items.isEmpty {
                problems.append("[\(guideline.id)][\(section.id)] empty section")
            }
        }
        return problems
    }

    static func duplicates(_ ids: [String], context: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids where !seen.insert(id).inserted {
            result.append("duplicate \(context): \(id)")
        }
        return result
    }
}
