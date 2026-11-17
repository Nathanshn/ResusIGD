import Foundation

public enum GuidelineCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case kardiologi
    case neurologi
    case trauma
    case alergiImunologi
    case metabolik
    case umum

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .kardiologi: "Kardiovaskular"
        case .neurologi: "Neurologi"
        case .trauma: "Trauma & Luka Bakar"
        case .alergiImunologi: "Alergi & Imunologi"
        case .metabolik: "Metabolik & Elektrolit"
        case .umum: "Umum"
        }
    }
}

public enum GuidelineSectionKind: String, Codable, Sendable {
    /// Time-critical targets ("Door-to-CT ≤ 20 menit").
    case targets
    /// Ordered, actionable steps.
    case checklist
    /// Drug regimens.
    case drugs
    /// Danger signs / red flags.
    case redFlags
    /// Plain notes.
    case notes
    /// Simple table rows; each item uses " | " as column separator, first item is the header.
    case table
}

public struct GuidelineSection: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var kind: GuidelineSectionKind
    public var items: [String]

    public init(id: String, title: String, kind: GuidelineSectionKind, items: [String]) {
        self.id = id
        self.title = title
        self.kind = kind
        self.items = items
    }
}

/// Interactive calculators that can be embedded inside a guideline.
public enum EmbeddedCalculator: String, Codable, Sendable, CaseIterable, Identifiable {
    case burnParkland
    case nihss
    case alteplase
    case gcs
    case sodiumCorrection
    case potassiumDrip

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .burnParkland: "Rule of Nines + Parkland"
        case .nihss: "Skor NIHSS"
        case .alteplase: "Dosis Alteplase (rtPA)"
        case .gcs: "GCS Dewasa & Pediatri"
        case .sodiumCorrection: "Koreksi Hiponatremia"
        case .potassiumDrip: "Drip KCl (Hipokalemia)"
        }
    }
}

public struct Guideline: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var category: GuidelineCategory
    public var keywords: [String]
    public var summary: String
    public var sections: [GuidelineSection]
    public var calculators: [EmbeddedCalculator]
    public var references: [String]

    public init(
        id: String, title: String, category: GuidelineCategory, keywords: [String], summary: String,
        sections: [GuidelineSection], calculators: [EmbeddedCalculator], references: [String]
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.keywords = keywords
        self.summary = summary
        self.sections = sections
        self.calculators = calculators
        self.references = references
    }
}
