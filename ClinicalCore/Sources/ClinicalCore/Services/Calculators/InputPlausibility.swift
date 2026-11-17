import Foundation

/// Detects implausible or mistyped patient inputs (e.g. 120 kg typed instead of 12 kg for a 2-year-old).
public enum InputPlausibility {
    public static let absoluteMinWeightKg = 0.3
    public static let absoluteMaxWeightKg = 300.0
    /// Ratio of entered / expected weight beyond which a warning is raised.
    public static let warningRatioHigh = 2.0
    public static let warningRatioLow = 0.5
    /// Ratio beyond which a likely typo is flagged as danger.
    public static let dangerRatioHigh = 3.0
    public static let dangerRatioLow = 1.0 / 3.0

    public static func pediatric(weightKg: Double?, ageMonths: Double?, lengthCm: Double?) -> [SafetyAlert] {
        var alerts: [SafetyAlert] = []
        guard let weightKg else { return alerts }

        if weightKg < absoluteMinWeightKg || weightKg > absoluteMaxWeightKg {
            alerts.append(SafetyAlert(.weightImplausible, .danger, title: "Berat badan tidak masuk akal",
                                      message: "BB \(ClinicalFormat.number(weightKg, maxDecimals: 1)) kg di luar rentang \(ClinicalFormat.number(absoluteMinWeightKg, maxDecimals: 1))–\(ClinicalFormat.number(absoluteMaxWeightKg)) kg. Periksa input."))
            return alerts
        }

        if let ageMonths, ageMonths >= 0, ageMonths < 13 * 12,
           let expected = PediatricWeightEstimator.apls(ageMonths: ageMonths)?.weightKg, expected > 0 {
            alerts += ratioAlerts(entered: weightKg, expected: expected, basis: "usia")
        } else if let lengthCm, lengthCm >= 46, lengthCm <= 150,
                  let expected = PediatricWeightEstimator.traubJohnson(lengthCm: lengthCm)?.weightKg {
            alerts += ratioAlerts(entered: weightKg, expected: expected, basis: "panjang badan")
        }

        if let ageMonths, ageMonths >= 18 * 12 {
            alerts.append(SafetyAlert(.adultAgeInPediatricModule, .info, title: "Usia dewasa",
                                      message: "Pasien ≥ 18 tahun: gunakan dosis dewasa / modul Titrasi."))
        }
        return alerts
    }

    public static func adult(weightKg: Double?, ageYears: Double?) -> [SafetyAlert] {
        var alerts: [SafetyAlert] = []
        if let weightKg {
            if weightKg < absoluteMinWeightKg || weightKg > absoluteMaxWeightKg {
                alerts.append(SafetyAlert(.weightImplausible, .danger, title: "Berat badan tidak masuk akal",
                                          message: "BB \(ClinicalFormat.number(weightKg, maxDecimals: 1)) kg di luar rentang yang mungkin. Periksa input."))
            } else if weightKg < 30 || weightKg > 200 {
                alerts.append(SafetyAlert(.weightOutlierForAge, .warning, title: "Berat badan tidak lazim untuk dewasa",
                                          message: "BB \(ClinicalFormat.number(weightKg, maxDecimals: 1)) kg. Pastikan tidak salah ketik (mis. 7 vs 70 kg)."))
            }
        }
        if let ageYears, ageYears < 18 {
            alerts.append(SafetyAlert(.pediatricAgeInAdultModule, .warning, title: "Pasien anak",
                                      message: "Usia < 18 tahun. Pertimbangkan modul Pediatri dan dosis berbasis BB."))
        }
        return alerts
    }

    static func ratioAlerts(entered: Double, expected: Double, basis: String) -> [SafetyAlert] {
        let ratio = entered / expected
        let expectedText = ClinicalFormat.number(expected, maxDecimals: 1)
        let enteredText = ClinicalFormat.number(entered, maxDecimals: 1)
        if ratio > dangerRatioHigh || ratio < dangerRatioLow {
            return [SafetyAlert(.weightOutlierForAge, .danger, title: "Kemungkinan salah ketik BB",
                                message: "BB \(enteredText) kg sangat berbeda dari perkiraan \(expectedText) kg berdasarkan \(basis) (×\(ClinicalFormat.number(ratio, maxDecimals: 1))). Verifikasi sebelum menghitung dosis.")]
        }
        if ratio > warningRatioHigh || ratio < warningRatioLow {
            return [SafetyAlert(.weightOutlierForAge, .warning, title: "BB tidak sesuai \(basis)",
                                message: "BB \(enteredText) kg vs perkiraan \(expectedText) kg berdasarkan \(basis). Pastikan input benar (gizi buruk/obesitas?).")]
        }
        return []
    }
}
