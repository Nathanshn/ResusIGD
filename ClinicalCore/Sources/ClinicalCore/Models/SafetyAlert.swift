import Foundation

/// Severity of a clinical safety alert. Ordered so that `.danger > .warning > .info`.
public enum AlertLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    case info = 0
    case warning = 1
    case danger = 2

    public static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Stable machine-readable identifiers for alerts so tests and UI logic never depend on display text.
public enum AlertCode: String, Codable, Sendable, CaseIterable {
    // Input validation
    case invalidInput
    case weightImplausible
    case weightOutlierForAge
    case ageOutOfFormulaRange
    case adultAgeInPediatricModule
    case pediatricAgeInAdultModule

    // Infusion / titration
    case doseAboveMaximum
    case doseBelowMinimum
    case doseAboveHardCeiling
    case peripheralConcentrationExceeded
    case centralLinePreferred
    case extravasationRisk
    case diluentPreferredAlternative
    case diluentCaution
    case diluentIncompatible
    case drugVolumeExceedsFinalVolume
    case pumpRateTooLow
    case pumpRateTooHigh
    case cumulativeBolusLimit

    // Pediatric dosing
    case cappedAtAdultSingleDose
    case cappedAtDailyMaximum
    case belowMinimumAge
    case belowMinimumWeight
    case aboveMaximumWeight
    case unitRoundingChangedDose
    case drugSpecificWarning

    // Fluids / burns / electrolytes
    case fluidCappedAtAdultVolume
    case maintenanceCappedAtAdultRate
    case burnWindowElapsed
    case burnBelowFormalResuscitationThreshold
    case sodiumNotLow
    case sodiumSevere
    case correctionLimit
    case impracticalVolume
    case potassiumRateExceeded
    case potassiumConcentrationExceeded
    case potassiumNotLow
    case alteplaseCapped
}

/// A single safety message shown in the UI. Text is Bahasa Indonesia; `code` is for logic/tests.
public struct SafetyAlert: Codable, Sendable, Hashable, Identifiable {
    public var id: String { code.rawValue + "|" + title }
    public let code: AlertCode
    public let level: AlertLevel
    public let title: String
    public let message: String

    public init(_ code: AlertCode, _ level: AlertLevel, title: String, message: String) {
        self.code = code
        self.level = level
        self.title = title
        self.message = message
    }
}

public extension Array where Element == SafetyAlert {
    /// Highest severity first, then stable by code.
    func sortedBySeverity() -> [SafetyAlert] {
        sorted { lhs, rhs in
            lhs.level != rhs.level ? lhs.level > rhs.level : lhs.code.rawValue < rhs.code.rawValue
        }
    }

    func contains(_ code: AlertCode) -> Bool { contains { $0.code == code } }

    var highestLevel: AlertLevel? { map(\.level).max() }
}
