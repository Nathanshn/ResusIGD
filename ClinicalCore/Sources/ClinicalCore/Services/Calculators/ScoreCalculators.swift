import Foundation

/// A scored option of a clinical scale item.
public struct ScoreOption: Sendable, Hashable, Identifiable {
    public var id: String { "\(score)|\(label)" }
    public let score: Int
    public let label: String
    /// True for “UN / tidak dapat dinilai” options (not added to the total).
    public let isUntestable: Bool

    public init(_ score: Int, _ label: String, untestable: Bool = false) {
        self.score = score
        self.label = label
        self.isUntestable = untestable
    }
}

public struct ScoreItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let options: [ScoreOption]
}

// MARK: - GCS

public enum GCSVariant: String, Sendable, CaseIterable, Identifiable {
    case adult
    case pediatric

    public var id: String { rawValue }
    public var label: String { self == .adult ? "Dewasa & Anak Verbal" : "Pediatri (< 2 thn / Pra-verbal)" }
}

public struct GCSResult: Sendable, Hashable {
    public let eye: Int
    public let verbal: Int?
    public let motor: Int
    /// Total; when verbal is not testable (intubated) the total excludes V and is shown as “T”.
    public let total: Int
    public let isIntubated: Bool
    public let notation: String
    public let severity: String
    public let severityLevel: AlertLevel
}

public enum GCSCalculator {
    public static func items(for variant: GCSVariant) -> [ScoreItem] {
        let eye = ScoreItem(id: "E", title: "Mata (E)", options: [
            ScoreOption(4, "Membuka spontan"),
            ScoreOption(3, variant == .adult ? "Membuka dengan perintah/suara" : "Membuka dengan suara"),
            ScoreOption(2, "Membuka dengan rangsang nyeri"),
            ScoreOption(1, "Tidak membuka")
        ])
        let verbal: ScoreItem
        let motor: ScoreItem
        switch variant {
        case .adult:
            verbal = ScoreItem(id: "V", title: "Verbal (V)", options: [
                ScoreOption(5, "Orientasi baik"),
                ScoreOption(4, "Bingung / disorientasi"),
                ScoreOption(3, "Kata-kata tidak tepat"),
                ScoreOption(2, "Suara tidak bermakna (mengerang)"),
                ScoreOption(1, "Tidak ada suara")
            ])
            motor = ScoreItem(id: "M", title: "Motorik (M)", options: [
                ScoreOption(6, "Mengikuti perintah"),
                ScoreOption(5, "Melokalisasi nyeri"),
                ScoreOption(4, "Menarik diri dari nyeri (fleksi normal)"),
                ScoreOption(3, "Fleksi abnormal (dekortikasi)"),
                ScoreOption(2, "Ekstensi (deserebrasi)"),
                ScoreOption(1, "Tidak ada gerakan")
            ])
        case .pediatric:
            verbal = ScoreItem(id: "V", title: "Verbal (V)", options: [
                ScoreOption(5, "Mengoceh / tersenyum, mengikuti benda"),
                ScoreOption(4, "Menangis, dapat ditenangkan / rewel"),
                ScoreOption(3, "Menangis terhadap nyeri, sulit ditenangkan"),
                ScoreOption(2, "Merintih terhadap nyeri"),
                ScoreOption(1, "Tidak ada suara")
            ])
            motor = ScoreItem(id: "M", title: "Motorik (M)", options: [
                ScoreOption(6, "Bergerak spontan / bertujuan"),
                ScoreOption(5, "Menarik diri terhadap sentuhan"),
                ScoreOption(4, "Menarik diri terhadap nyeri"),
                ScoreOption(3, "Fleksi abnormal (dekortikasi)"),
                ScoreOption(2, "Ekstensi (deserebrasi)"),
                ScoreOption(1, "Tidak ada gerakan")
            ])
        }
        return [eye, verbal, motor]
    }

    public static func calculate(eye: Int, verbal: Int?, motor: Int) -> GCSResult? {
        guard (1...4).contains(eye), (1...6).contains(motor) else { return nil }
        if let verbal, !(1...5).contains(verbal) { return nil }
        let intubated = verbal == nil
        let total = eye + (verbal ?? 0) + motor
        let notation = intubated ? "E\(eye)VT M\(motor) = \(total)T" : "E\(eye)V\(verbal ?? 0)M\(motor) = \(total)"

        let severity: String
        let level: AlertLevel
        if intubated {
            severity = "Verbal tidak dapat dinilai (terintubasi) — laporkan sebagai \(total)T"
            level = .warning
        } else if total <= 8 {
            severity = "Cedera otak berat (GCS ≤ 8) — amankan jalan napas definitif"
            level = .danger
        } else if total <= 12 {
            severity = "Cedera otak sedang (GCS 9–12)"
            level = .warning
        } else {
            severity = "Cedera otak ringan (GCS 13–15)"
            level = .info
        }
        return GCSResult(eye: eye, verbal: verbal, motor: motor, total: total, isIntubated: intubated,
                         notation: notation, severity: severity, severityLevel: level)
    }
}

// MARK: - NIHSS

public struct NIHSSResult: Sendable, Hashable {
    public let total: Int
    public let answered: Int
    public let itemCount: Int
    public let severity: String

    public var isComplete: Bool { answered == itemCount }
}

public enum NIHSSCalculator {
    public static let maxScore = 42

    private static func motorOptions() -> [ScoreOption] {
        [
            ScoreOption(0, "Tidak ada drift"),
            ScoreOption(1, "Drift, tidak menyentuh kasur"),
            ScoreOption(2, "Ada usaha melawan gravitasi, jatuh ke kasur"),
            ScoreOption(3, "Tidak ada usaha melawan gravitasi"),
            ScoreOption(4, "Tidak ada gerakan"),
            ScoreOption(0, "UN — amputasi / fusi sendi", untestable: true)
        ]
    }

    public static let items: [ScoreItem] = [
        ScoreItem(id: "1a", title: "1a. Tingkat kesadaran", options: [
            ScoreOption(0, "Sadar penuh"),
            ScoreOption(1, "Somnolen (bangun dengan rangsang ringan)"),
            ScoreOption(2, "Stupor (perlu rangsang berulang/nyeri)"),
            ScoreOption(3, "Koma / hanya refleks")
        ]),
        ScoreItem(id: "1b", title: "1b. Pertanyaan (bulan & usia)", options: [
            ScoreOption(0, "Keduanya benar"),
            ScoreOption(1, "Satu benar"),
            ScoreOption(2, "Keduanya salah")
        ]),
        ScoreItem(id: "1c", title: "1c. Perintah (buka-tutup mata, genggam)", options: [
            ScoreOption(0, "Keduanya benar"),
            ScoreOption(1, "Satu benar"),
            ScoreOption(2, "Keduanya salah")
        ]),
        ScoreItem(id: "2", title: "2. Gerakan bola mata horizontal", options: [
            ScoreOption(0, "Normal"),
            ScoreOption(1, "Paresis gaze parsial"),
            ScoreOption(2, "Deviasi paksa / paresis total")
        ]),
        ScoreItem(id: "3", title: "3. Lapang pandang", options: [
            ScoreOption(0, "Normal"),
            ScoreOption(1, "Hemianopia parsial"),
            ScoreOption(2, "Hemianopia komplet"),
            ScoreOption(3, "Hemianopia bilateral / buta")
        ]),
        ScoreItem(id: "4", title: "4. Paresis wajah", options: [
            ScoreOption(0, "Normal"),
            ScoreOption(1, "Minor (lipatan nasolabial datar)"),
            ScoreOption(2, "Parsial (wajah bawah)"),
            ScoreOption(3, "Komplet (atas & bawah)")
        ]),
        ScoreItem(id: "5a", title: "5a. Motorik lengan kiri", options: motorOptions()),
        ScoreItem(id: "5b", title: "5b. Motorik lengan kanan", options: motorOptions()),
        ScoreItem(id: "6a", title: "6a. Motorik tungkai kiri", options: motorOptions()),
        ScoreItem(id: "6b", title: "6b. Motorik tungkai kanan", options: motorOptions()),
        ScoreItem(id: "7", title: "7. Ataksia anggota gerak", options: [
            ScoreOption(0, "Tidak ada"),
            ScoreOption(1, "Pada satu ekstremitas"),
            ScoreOption(2, "Pada dua ekstremitas"),
            ScoreOption(0, "UN — amputasi / fusi sendi", untestable: true)
        ]),
        ScoreItem(id: "8", title: "8. Sensorik", options: [
            ScoreOption(0, "Normal"),
            ScoreOption(1, "Gangguan ringan–sedang"),
            ScoreOption(2, "Gangguan berat / total")
        ]),
        ScoreItem(id: "9", title: "9. Bahasa (afasia)", options: [
            ScoreOption(0, "Normal"),
            ScoreOption(1, "Afasia ringan–sedang"),
            ScoreOption(2, "Afasia berat"),
            ScoreOption(3, "Mutisme / afasia global")
        ]),
        ScoreItem(id: "10", title: "10. Disartria", options: [
            ScoreOption(0, "Normal"),
            ScoreOption(1, "Ringan–sedang"),
            ScoreOption(2, "Berat / tidak dapat dimengerti"),
            ScoreOption(0, "UN — terintubasi / hambatan fisik", untestable: true)
        ]),
        ScoreItem(id: "11", title: "11. Ekstinsi / inatensi (neglect)", options: [
            ScoreOption(0, "Tidak ada"),
            ScoreOption(1, "Satu modalitas"),
            ScoreOption(2, "Berat / lebih dari satu modalitas")
        ])
    ]

    /// `selections` maps item id → chosen option.
    public static func calculate(selections: [String: ScoreOption]) -> NIHSSResult {
        let validIDs = Set(items.map(\.id))
        let chosen = selections.filter { validIDs.contains($0.key) }
        let total = chosen.values.reduce(0) { $0 + ($1.isUntestable ? 0 : $1.score) }
        return NIHSSResult(total: total, answered: chosen.count, itemCount: items.count, severity: severity(for: total))
    }

    public static func severity(for total: Int) -> String {
        switch total {
        case 0: "Tidak ada defisit stroke"
        case 1...4: "Stroke ringan (1–4)"
        case 5...15: "Stroke sedang (5–15)"
        case 16...20: "Stroke sedang–berat (16–20)"
        default: "Stroke berat (21–42)"
        }
    }
}
