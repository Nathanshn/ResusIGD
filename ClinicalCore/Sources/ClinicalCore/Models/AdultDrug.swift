import Foundation

/// Dose units supported by the continuous-infusion titration calculator.
public enum InfusionDoseUnit: String, Codable, Sendable, CaseIterable {
    case mcgPerKgPerMin
    case mcgPerMin
    case mgPerMin
    case mgPerHour

    public var label: String {
        switch self {
        case .mcgPerKgPerMin: "mcg/kg/menit"
        case .mcgPerMin: "mcg/menit"
        case .mgPerMin: "mg/menit"
        case .mgPerHour: "mg/jam"
        }
    }

    public var isWeightBased: Bool { self == .mcgPerKgPerMin }

    /// Converts a dose in this unit to mg per minute.
    public func mgPerMinute(dose: Double, weightKg: Double) -> Double {
        switch self {
        case .mcgPerKgPerMin: dose * weightKg / 1000
        case .mcgPerMin: dose / 1000
        case .mgPerMin: dose
        case .mgPerHour: dose / 60
        }
    }

    /// Inverse of `mgPerMinute(dose:weightKg:)`.
    public func dose(fromMgPerMinute mgPerMin: Double, weightKg: Double) -> Double {
        switch self {
        case .mcgPerKgPerMin: weightKg > 0 ? mgPerMin * 1000 / weightKg : 0
        case .mcgPerMin: mgPerMin * 1000
        case .mgPerMin: mgPerMin
        case .mgPerHour: mgPerMin * 60
        }
    }
}

public enum ConcentrationDisplayUnit: String, Codable, Sendable {
    case mcgPerML
    case mgPerML

    public var label: String { self == .mcgPerML ? "mcg/mL" : "mg/mL" }

    public func value(fromMgPerML mgPerML: Double) -> Double {
        self == .mcgPerML ? mgPerML * 1000 : mgPerML
    }
}

public enum Diluent: String, Codable, Sendable, CaseIterable, Identifiable {
    case nacl09
    case dextrose5

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .nacl09: "NaCl 0,9%"
        case .dextrose5: "Dextrose 5% (D5%)"
        }
    }

    public var shortLabel: String { self == .nacl09 ? "NaCl 0,9%" : "D5%" }
}

public enum CompatibilityStatus: String, Codable, Sendable {
    case preferred
    case compatible
    case caution
    case incompatible
}

public struct DiluentRule: Codable, Sendable, Hashable {
    public var diluent: Diluent
    public var status: CompatibilityStatus
    public var note: String

    public init(diluent: Diluent, status: CompatibilityStatus, note: String) {
        self.diluent = diluent
        self.status = status
        self.note = note
    }
}

/// Strength of one ampoule / vial as supplied.
public struct AmpouleStrength: Codable, Sendable, Hashable {
    public var mg: Double
    public var mL: Double

    public init(mg: Double, mL: Double) {
        self.mg = mg
        self.mL = mL
    }

    public var mgPerML: Double { mL > 0 ? mg / mL : 0 }

    public var label: String {
        "\(ClinicalFormat.number(mg)) mg / \(ClinicalFormat.number(mL)) mL"
    }
}

public enum AdministrationMode: String, Codable, Sendable {
    case infusion
    case bolus
}

/// One dosing regimen (indication) for an adult high-alert drug.
public struct AdultRegimen: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var indication: String
    public var mode: AdministrationMode
    /// Infusion unit. For bolus regimens the dose is always expressed in mg.
    public var unit: InfusionDoseUnit?
    public var minDose: Double
    public var maxDose: Double
    public var defaultDose: Double
    public var step: Double
    /// Absolute ceiling: anything above is flagged as a danger alert.
    public var hardCeilingDose: Double?
    /// Bolus only: maximum cumulative dose (mg) per episode.
    public var maxCumulativeMg: Double?
    /// Bolus only: free-text repeat interval, e.g. "tiap 3–5 menit".
    public var repeatInterval: String?
    public var administration: String
    public var notes: [String]

    public init(
        id: String, label: String, indication: String, mode: AdministrationMode,
        unit: InfusionDoseUnit?, minDose: Double, maxDose: Double, defaultDose: Double, step: Double,
        hardCeilingDose: Double? = nil, maxCumulativeMg: Double? = nil, repeatInterval: String? = nil,
        administration: String, notes: [String] = []
    ) {
        self.id = id
        self.label = label
        self.indication = indication
        self.mode = mode
        self.unit = unit
        self.minDose = minDose
        self.maxDose = maxDose
        self.defaultDose = defaultDose
        self.step = step
        self.hardCeilingDose = hardCeilingDose
        self.maxCumulativeMg = maxCumulativeMg
        self.repeatInterval = repeatInterval
        self.administration = administration
        self.notes = notes
    }

    public var doseUnitLabel: String { unit?.label ?? "mg" }

    /// Upper bound offered by the slider: the hard ceiling if present, else the usual maximum.
    public var sliderUpperBound: Double { max(hardCeilingDose ?? maxDose, maxDose) }
}

/// Adult high-alert drug monograph used by Module 1.
public struct AdultDrug: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var drugClass: String
    public var isHighAlert: Bool
    public var ampoule: AmpouleStrength
    public var defaultAmpouleCount: Double
    public var defaultFinalVolumeML: Double
    public var concentrationDisplayUnit: ConcentrationDisplayUnit
    public var diluentRules: [DiluentRule]
    /// Max concentration acceptable through a peripheral line (mg/mL). `nil` = no specific limit.
    public var peripheralMaxConcentrationMgPerML: Double?
    public var centralLinePreferred: Bool
    public var extravasationWarning: String?
    public var regimens: [AdultRegimen]
    public var preparationNotes: [String]
    public var monograph: String
    public var references: [String]

    public init(
        id: String, name: String, drugClass: String, isHighAlert: Bool, ampoule: AmpouleStrength,
        defaultAmpouleCount: Double, defaultFinalVolumeML: Double, concentrationDisplayUnit: ConcentrationDisplayUnit,
        diluentRules: [DiluentRule], peripheralMaxConcentrationMgPerML: Double?, centralLinePreferred: Bool,
        extravasationWarning: String?, regimens: [AdultRegimen], preparationNotes: [String], monograph: String,
        references: [String]
    ) {
        self.id = id
        self.name = name
        self.drugClass = drugClass
        self.isHighAlert = isHighAlert
        self.ampoule = ampoule
        self.defaultAmpouleCount = defaultAmpouleCount
        self.defaultFinalVolumeML = defaultFinalVolumeML
        self.concentrationDisplayUnit = concentrationDisplayUnit
        self.diluentRules = diluentRules
        self.peripheralMaxConcentrationMgPerML = peripheralMaxConcentrationMgPerML
        self.centralLinePreferred = centralLinePreferred
        self.extravasationWarning = extravasationWarning
        self.regimens = regimens
        self.preparationNotes = preparationNotes
        self.monograph = monograph
        self.references = references
    }

    public func rule(for diluent: Diluent) -> DiluentRule? {
        diluentRules.first { $0.diluent == diluent }
    }

    public var defaultRegimen: AdultRegimen? { regimens.first }

    public var hasInfusionRegimen: Bool { regimens.contains { $0.mode == .infusion } }
}
