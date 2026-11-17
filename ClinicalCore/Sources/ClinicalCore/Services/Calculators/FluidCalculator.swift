import Foundation

public struct FluidBolus: Sendable, Hashable {
    public let mLPerKg: Double
    public let volumeML: Double
    public let cappedAtAdultVolume: Bool
    public let alerts: [SafetyAlert]
}

public struct MaintenanceFluid: Sendable, Hashable {
    /// 4-2-1 rule (mL/jam).
    public let hourlyML: Double
    /// 100-50-20 rule (mL/24 jam).
    public let dailyML: Double
    public let rate: RateTriple
    public let hourlyCapped: Bool
    public let dailyCapped: Bool
    public let breakdown: String
    public let alerts: [SafetyAlert]
}

public enum FluidCalculator {
    public static let defaultBolusMLPerKg = 20.0
    /// Adult single bolus ceiling (ATLS: 1 L isotonic crystalloid).
    public static let adultBolusCapML = 1000.0
    /// Usual adult maintenance ceiling.
    public static let adultMaintenanceHourlyCapML = 100.0
    public static let adultMaintenanceDailyCapML = 2400.0

    /// Isotonic fluid bolus (NaCl 0,9% / RL), default 20 mL/kg, capped at adult 1000 mL.
    public static func bolus(weightKg: Double, mLPerKg: Double = defaultBolusMLPerKg) -> FluidBolus? {
        guard weightKg > 0, mLPerKg > 0 else { return nil }
        let raw = weightKg * mLPerKg
        let capped = raw > adultBolusCapML
        var alerts: [SafetyAlert] = []
        if capped {
            alerts.append(SafetyAlert(.fluidCappedAtAdultVolume, .warning, title: "Dibatasi dosis dewasa",
                                      message: "\(ClinicalFormat.number(mLPerKg)) mL/kg × \(ClinicalFormat.number(weightKg, maxDecimals: 1)) kg = \(ClinicalFormat.volume(raw)) mL; dibatasi \(ClinicalFormat.volume(adultBolusCapML)) mL per bolus. Evaluasi ulang setelah tiap bolus."))
        }
        return FluidBolus(mLPerKg: mLPerKg, volumeML: min(raw, adultBolusCapML), cappedAtAdultVolume: capped, alerts: alerts)
    }

    /// Holliday-Segar maintenance (4-2-1 per hour and 100-50-20 per day).
    public static func hollidaySegar(weightKg: Double) -> MaintenanceFluid? {
        guard weightKg > 0, weightKg.isFinite else { return nil }
        let first = min(weightKg, 10)
        let second = min(max(weightKg - 10, 0), 10)
        let rest = max(weightKg - 20, 0)

        let hourlyRaw = first * 4 + second * 2 + rest * 1
        let dailyRaw = first * 100 + second * 50 + rest * 20
        let hourlyCapped = hourlyRaw > adultMaintenanceHourlyCapML
        let dailyCapped = dailyRaw > adultMaintenanceDailyCapML
        let hourly = min(hourlyRaw, adultMaintenanceHourlyCapML)
        let daily = min(dailyRaw, adultMaintenanceDailyCapML)

        var parts = ["\(ClinicalFormat.number(first, maxDecimals: 1)) kg × 4"]
        if second > 0 { parts.append("\(ClinicalFormat.number(second, maxDecimals: 1)) kg × 2") }
        if rest > 0 { parts.append("\(ClinicalFormat.number(rest, maxDecimals: 1)) kg × 1") }

        var alerts: [SafetyAlert] = []
        if hourlyCapped || dailyCapped {
            alerts.append(SafetyAlert(.maintenanceCappedAtAdultRate, .info, title: "Dibatasi kebutuhan dewasa",
                                      message: "Hasil 4-2-1 = \(ClinicalFormat.rate(hourlyRaw)) mL/jam; dibatasi \(ClinicalFormat.number(adultMaintenanceHourlyCapML)) mL/jam (\(ClinicalFormat.number(adultMaintenanceDailyCapML)) mL/24 jam)."))
        }

        return MaintenanceFluid(
            hourlyML: hourly,
            dailyML: daily,
            rate: RateTriple(mLPerHour: hourly),
            hourlyCapped: hourlyCapped,
            dailyCapped: dailyCapped,
            breakdown: parts.joined(separator: " + ") + " = \(ClinicalFormat.rate(hourlyRaw)) mL/jam",
            alerts: alerts
        )
    }
}
