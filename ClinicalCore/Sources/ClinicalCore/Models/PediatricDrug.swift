import Foundation

public enum PediatricCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case antikonvulsan
    case antipiretikAnalgetik
    case antiemetik
    case antibiotik
    case resusitasiRespirasi

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .antikonvulsan: "Antikonvulsan"
        case .antipiretikAnalgetik: "Antipiretik & Analgetik"
        case .antiemetik: "Antiemetik"
        case .antibiotik: "Antibiotik"
        case .resusitasiRespirasi: "Resusitasi & Respirasi"
        }
    }
}

public enum DrugRoute: String, Codable, Sendable, CaseIterable {
    case oral
    case intravena
    case intramuskular
    case rektal
    case intranasal
    case bukal
    case nebulisasi
    case intraoseus

    public var label: String {
        switch self {
        case .oral: "Oral"
        case .intravena: "IV"
        case .intramuskular: "IM"
        case .rektal: "Rektal"
        case .intranasal: "Intranasal"
        case .bukal: "Bukal"
        case .nebulisasi: "Nebulisasi"
        case .intraoseus: "IO"
        }
    }
}

public enum FormulationKind: String, Codable, Sendable {
    /// Liquid with a concentration (mg/mL): syrup, drops, injection, nebule.
    case liquid
    /// Discrete unit: tablet, suppository, rectal tube.
    case unit
}

public struct Formulation: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var route: DrugRoute
    public var kind: FormulationKind
    public var mgPerML: Double?
    public var mgPerUnit: Double?
    /// e.g. "supositoria", "tablet", "tube".
    public var unitName: String?
    /// Smallest allowed fraction of a unit: 1 = whole only, 0.5 = may be halved.
    public var unitDivisibility: Double?
    public var notes: String?

    public init(
        id: String, label: String, route: DrugRoute, kind: FormulationKind, mgPerML: Double? = nil,
        mgPerUnit: Double? = nil, unitName: String? = nil, unitDivisibility: Double? = nil, notes: String? = nil
    ) {
        self.id = id
        self.label = label
        self.route = route
        self.kind = kind
        self.mgPerML = mgPerML
        self.mgPerUnit = mgPerUnit
        self.unitName = unitName
        self.unitDivisibility = unitDivisibility
        self.notes = notes
    }
}

/// Fixed dose by weight band (e.g. rectal diazepam 5 mg if < 12 kg, 10 mg if ≥ 12 kg).
public struct WeightBand: Codable, Sendable, Hashable {
    /// Inclusive lower bound (kg).
    public var minKg: Double
    /// Exclusive upper bound (kg). `nil` = no upper bound.
    public var maxKg: Double?
    public var doseMg: Double

    public init(minKg: Double, maxKg: Double?, doseMg: Double) {
        self.minKg = minKg
        self.maxKg = maxKg
        self.doseMg = doseMg
    }

    public func contains(_ weightKg: Double) -> Bool {
        weightKg >= minKg && (maxKg.map { weightKg < $0 } ?? true)
    }
}

public struct PediatricRegimen: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var indication: String
    public var route: DrugRoute
    public var mgPerKgMin: Double?
    public var mgPerKgDefault: Double?
    public var mgPerKgMax: Double?
    public var fixedDoseBands: [WeightBand]?
    public var frequency: String
    /// Number of doses per 24 h used for the daily-maximum check. `nil` = single/as-needed dose.
    public var dosesPerDay: Int?
    /// Adult single-dose ceiling (mg). Weight-based doses are capped here.
    public var maxSingleDoseMg: Double?
    /// Adult daily ceiling (mg / 24 h).
    public var maxDailyDoseMg: Double?
    /// Pediatric daily ceiling (mg/kg/24 h).
    public var maxDailyMgPerKg: Double?
    public var minAgeMonths: Double?
    public var minWeightKg: Double?
    public var maxWeightKg: Double?
    /// IDs of formulations this regimen may be given with.
    public var formulationIDs: [String]
    public var administration: String
    public var notes: [String]

    public init(
        id: String, label: String, indication: String, route: DrugRoute, mgPerKgMin: Double? = nil, mgPerKgDefault: Double? = nil,
        mgPerKgMax: Double? = nil, fixedDoseBands: [WeightBand]? = nil, frequency: String, dosesPerDay: Int? = nil,
        maxSingleDoseMg: Double? = nil, maxDailyDoseMg: Double? = nil, maxDailyMgPerKg: Double? = nil,
        minAgeMonths: Double? = nil, minWeightKg: Double? = nil, maxWeightKg: Double? = nil,
        formulationIDs: [String], administration: String, notes: [String] = []
    ) {
        self.id = id
        self.label = label
        self.indication = indication
        self.route = route
        self.mgPerKgMin = mgPerKgMin
        self.mgPerKgDefault = mgPerKgDefault
        self.mgPerKgMax = mgPerKgMax
        self.fixedDoseBands = fixedDoseBands
        self.frequency = frequency
        self.dosesPerDay = dosesPerDay
        self.maxSingleDoseMg = maxSingleDoseMg
        self.maxDailyDoseMg = maxDailyDoseMg
        self.maxDailyMgPerKg = maxDailyMgPerKg
        self.minAgeMonths = minAgeMonths
        self.minWeightKg = minWeightKg
        self.maxWeightKg = maxWeightKg
        self.formulationIDs = formulationIDs
        self.administration = administration
        self.notes = notes
    }

    public var isWeightBanded: Bool { !(fixedDoseBands ?? []).isEmpty }
}

public struct PediatricDrug: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var category: PediatricCategory
    public var formulations: [Formulation]
    public var regimens: [PediatricRegimen]
    public var warnings: [String]
    public var monograph: String
    public var references: [String]

    public init(
        id: String, name: String, category: PediatricCategory, formulations: [Formulation],
        regimens: [PediatricRegimen], warnings: [String], monograph: String, references: [String]
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.formulations = formulations
        self.regimens = regimens
        self.warnings = warnings
        self.monograph = monograph
        self.references = references
    }

    public func formulations(for regimen: PediatricRegimen) -> [Formulation] {
        regimen.formulationIDs.compactMap { id in formulations.first { $0.id == id } }
    }
}
