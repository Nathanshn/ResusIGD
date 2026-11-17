import Foundation

/// Builds a chronological SOAP-formatted resuscitation note ready to paste into the EMR / rekam medis.
public enum SOAPLogFormatter {
    public static func format(
        session: ResusSessionEngine,
        now: Date,
        timeZone: TimeZone = .current,
        patientInfo: String? = nil
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        func time(_ date: Date) -> String {
            let c = calendar.dateComponents([.hour, .minute, .second], from: date)
            return [c.hour ?? 0, c.minute ?? 0, c.second ?? 0].map { $0 < 10 ? "0\($0)" : "\($0)" }.joined(separator: ":")
        }
        func day(_ date: Date) -> String {
            let c = calendar.dateComponents([.day, .month, .year], from: date)
            let dd = (c.day ?? 0) < 10 ? "0\(c.day ?? 0)" : "\(c.day ?? 0)"
            let mm = (c.month ?? 0) < 10 ? "0\(c.month ?? 0)" : "\(c.month ?? 0)"
            return "\(dd)/\(mm)/\(c.year ?? 0)"
        }
        func offset(_ date: Date) -> String {
            "+" + ResusSessionEngine.clock(date.timeIntervalSince(session.startedAt))
        }

        let end = session.endedAt ?? now
        let duration = ResusSessionEngine.clock(end.timeIntervalSince(session.startedAt))
        let interventions = session.events.filter { $0.kind != .sessionStart && $0.kind != .sessionEnd }

        var lines: [String] = []
        lines.append("LOG RESUSITASI IGD — \(session.mode.label.uppercased())")
        lines.append("Tanggal \(day(session.startedAt)) · Mulai \(time(session.startedAt)) · \(session.endedAt == nil ? "Berlangsung" : "Selesai \(time(end))") · Durasi \(duration)")
        if let patientInfo, !patientInfo.isEmpty {
            lines.append("Pasien: \(patientInfo)")
        }
        lines.append("")

        // S
        lines.append("S:")
        switch session.mode {
        case .cardiacArrest:
            lines.append("- Pasien ditemukan/dinyatakan henti jantung; sesi resusitasi dimulai pukul \(time(session.startedAt)).")
        case .statusEpilepticus:
            lines.append("- Kejang berlangsung; onset tercatat pukul \(time(session.seizureOnset)).")
        }
        lines.append("")

        // O
        lines.append("O: Kronologi tindakan")
        if interventions.isEmpty {
            lines.append("- (belum ada tindakan tercatat)")
        } else {
            for event in interventions {
                lines.append("- [\(time(event.timestamp))] (\(offset(event.timestamp))) \(event.label)")
            }
        }
        lines.append("")

        // A
        lines.append("A:")
        switch session.mode {
        case .cardiacArrest:
            let epi = session.count(of: .epinephrine)
            let shocks = session.count(of: .defibrillation)
            let amio = session.events.filter { $0.kind == .amiodarone }.map(\.label)
            lines.append("- Henti jantung. Epinefrin: \(epi)×. Defibrilasi: \(shocks)×.\(amio.isEmpty ? "" : " " + amio.joined(separator: ", ") + ".")")
            if let rosc = session.events.first(where: { $0.kind == .rosc }) {
                lines.append("- ROSC tercapai pukul \(time(rosc.timestamp)) (\(offset(rosc.timestamp)) dari awal resusitasi).")
            } else {
                lines.append("- ROSC belum tercapai / tidak tercatat.")
            }
        case .statusEpilepticus:
            let benzo = session.count(of: .benzodiazepine)
            let second = session.count(of: .secondLineAntiseizure)
            lines.append("- Status epileptikus. Benzodiazepin: \(benzo)×. Antikonvulsan lini kedua: \(second)×.")
            if let stopped = session.events.first(where: { $0.kind == .seizureStopped }) {
                let minutes = stopped.timestamp.timeIntervalSince(session.seizureOnset) / 60
                lines.append("- Kejang berhenti pukul \(time(stopped.timestamp)) (± \(ClinicalFormat.number(minutes, maxDecimals: 0)) menit sejak onset).")
            } else {
                lines.append("- Fase saat ini: \(session.seizurePhase(at: end).label).")
            }
        }
        lines.append("")

        // P
        lines.append("P:")
        switch session.mode {
        case .cardiacArrest:
            if session.events.contains(where: { $0.kind == .rosc }) {
                lines.append("- Perawatan pasca-ROSC: SpO2 92–98%, MAP ≥ 65 mmHg, EKG 12 sadapan, kontrol suhu, rujuk ICU/ICCU.")
            } else {
                lines.append("- Lanjutkan sesuai algoritma ACLS / keputusan tim.")
            }
        case .statusEpilepticus:
            lines.append("- Observasi kesadaran & napas, cari etiologi (GDS, elektrolit, infeksi, toksik), rencana rawat/ICU sesuai respons.")
        }
        lines.append("")
        lines.append("Dicatat dengan ResusIGD — verifikasi oleh dokter penanggung jawab.")
        return lines.joined(separator: "\n")
    }
}
