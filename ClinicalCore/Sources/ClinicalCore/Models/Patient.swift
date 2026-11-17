import Foundation

public enum Sex: String, Codable, Sendable, CaseIterable, Identifiable {
    case male
    case female

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .male: "Laki-laki"
        case .female: "Perempuan"
        }
    }
}

/// Age expressed as years / months / days as typed by the clinician.
public struct PatientAge: Codable, Sendable, Hashable {
    public var years: Int
    public var months: Int
    public var days: Int

    public init(years: Int = 0, months: Int = 0, days: Int = 0) {
        self.years = years
        self.months = months
        self.days = days
    }

    public static let daysPerMonth = 30.4375

    /// Total age in (fractional) months.
    public var totalMonths: Double {
        Double(years) * 12 + Double(months) + Double(days) / Self.daysPerMonth
    }

    /// Total age in (fractional) years.
    public var totalYears: Double { totalMonths / 12 }

    public var isZero: Bool { years == 0 && months == 0 && days == 0 }

    /// Indonesian display string, e.g. "2 thn 3 bln".
    public var label: String {
        var parts: [String] = []
        if years > 0 { parts.append("\(years) thn") }
        if months > 0 { parts.append("\(months) bln") }
        if days > 0 { parts.append("\(days) hari") }
        return parts.isEmpty ? "0 hari" : parts.joined(separator: " ")
    }
}

/// Venous access used for an infusion — drives peripheral concentration guardrails.
public enum VascularAccess: String, Codable, Sendable, CaseIterable, Identifiable {
    case peripheral
    case central

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .peripheral: "Vena Perifer"
        case .central: "CVC (Vena Sentral)"
        }
    }
}
