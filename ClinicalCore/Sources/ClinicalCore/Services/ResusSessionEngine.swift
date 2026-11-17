import Foundation

public enum ResusMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case cardiacArrest
    case statusEpilepticus

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cardiacArrest: "Code Blue / Henti Jantung"
        case .statusEpilepticus: "Status Epileptikus"
        }
    }
}

/// Category of a logged intervention (drives reminders and the SOAP summary).
public enum ResusEventKind: String, Codable, Sendable, CaseIterable {
    case cprStart
    case epinephrine
    case defibrillation
    case amiodarone
    case airway
    case rosc
    case benzodiazepine
    case secondLineAntiseizure
    case seizureStopped
    case rhythmCheck
    case note
    case sessionStart
    case sessionEnd
}

public struct ResusEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var kind: ResusEventKind
    public var label: String

    public init(id: UUID = UUID(), timestamp: Date, kind: ResusEventKind, label: String) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.label = label
    }
}

/// One-tap action button definition.
public struct ResusQuickAction: Sendable, Hashable, Identifiable {
    public var id: String { label }
    public let label: String
    public let kind: ResusEventKind
    public let systemImage: String

    public init(label: String, kind: ResusEventKind, systemImage: String) {
        self.label = label
        self.kind = kind
        self.systemImage = systemImage
    }
}

public enum SeizurePhase: Int, Sendable, CaseIterable, Comparable {
    case stabilization = 0      // 0–5 menit
    case initialTherapy = 1     // 5–20 menit
    case secondTherapy = 2      // 20–40 menit
    case refractory = 3         // > 40 menit

    public static func < (lhs: SeizurePhase, rhs: SeizurePhase) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .stabilization: "0–5 menit · Stabilisasi"
        case .initialTherapy: "5–20 menit · Terapi awal (benzodiazepin)"
        case .secondTherapy: "20–40 menit · Terapi lini kedua"
        case .refractory: "> 40 menit · Refrakter (ICU / anestesi)"
        }
    }

    public var action: String {
        switch self {
        case .stabilization: "ABC, O2, monitor, cek GDS, akses IV, catat waktu mulai kejang."
        case .initialTherapy: "Benzodiazepin: diazepam IV 0,2–0,3 mg/kg (maks 10 mg) / midazolam IM 0,2 mg/kg (maks 10 mg). Boleh diulang 1×."
        case .secondTherapy: "Fenitoin 20 mg/kg IV (dalam NaCl 0,9%) atau levetirasetam 60 mg/kg (maks 4.500 mg) atau valproat 40 mg/kg (maks 3.000 mg) atau fenobarbital 20 mg/kg."
        case .refractory: "Konsultasi ICU/anestesi: intubasi, infus midazolam/propofol/tiopental, monitor EEG."
        }
    }

    /// Phase start in seconds from seizure onset.
    public var startSeconds: TimeInterval {
        switch self {
        case .stabilization: 0
        case .initialTherapy: 5 * 60
        case .secondTherapy: 20 * 60
        case .refractory: 40 * 60
        }
    }
}

/// Pure timing engine for the resuscitation timer; the UI only feeds it `now`.
public struct ResusSessionEngine: Codable, Sendable, Hashable {
    public static let cprCycleSeconds: TimeInterval = 120
    public static let epinephrineIntervalOptions: [TimeInterval] = [180, 240, 300]

    public var mode: ResusMode
    public var startedAt: Date
    public var endedAt: Date?
    public var events: [ResusEvent]
    /// When the current CPR cycle started (reset at each rhythm check / "RJP Dimulai").
    public var cycleStartedAt: Date?
    public var epinephrineInterval: TimeInterval

    public init(mode: ResusMode, startedAt: Date, epinephrineInterval: TimeInterval = 240) {
        self.mode = mode
        self.startedAt = startedAt
        self.events = [ResusEvent(timestamp: startedAt, kind: .sessionStart, label: "Sesi \(mode.label) dimulai")]
        self.cycleStartedAt = nil
        self.epinephrineInterval = epinephrineInterval
    }

    public static func quickActions(for mode: ResusMode) -> [ResusQuickAction] {
        switch mode {
        case .cardiacArrest:
            [
                ResusQuickAction(label: "RJP Dimulai", kind: .cprStart, systemImage: "heart.fill"),
                ResusQuickAction(label: "Epinefrin 1 mg IV", kind: .epinephrine, systemImage: "syringe.fill"),
                ResusQuickAction(label: "Defibrilasi 200J", kind: .defibrillation, systemImage: "bolt.heart.fill"),
                ResusQuickAction(label: "Amiodaron 300 mg", kind: .amiodarone, systemImage: "syringe"),
                ResusQuickAction(label: "Amiodaron 150 mg", kind: .amiodarone, systemImage: "syringe"),
                ResusQuickAction(label: "Cek Irama", kind: .rhythmCheck, systemImage: "waveform.path.ecg"),
                ResusQuickAction(label: "Intubasi ETT", kind: .airway, systemImage: "lungs.fill"),
                ResusQuickAction(label: "ROSC", kind: .rosc, systemImage: "checkmark.seal.fill")
            ]
        case .statusEpilepticus:
            [
                ResusQuickAction(label: "Kejang Dimulai (onset)", kind: .note, systemImage: "bolt.fill"),
                ResusQuickAction(label: "Cek GDS", kind: .note, systemImage: "drop.fill"),
                ResusQuickAction(label: "Diazepam IV", kind: .benzodiazepine, systemImage: "syringe.fill"),
                ResusQuickAction(label: "Diazepam Rektal", kind: .benzodiazepine, systemImage: "syringe"),
                ResusQuickAction(label: "Midazolam IM", kind: .benzodiazepine, systemImage: "syringe"),
                ResusQuickAction(label: "Fenitoin 20 mg/kg IV", kind: .secondLineAntiseizure, systemImage: "cross.vial.fill"),
                ResusQuickAction(label: "Intubasi ETT", kind: .airway, systemImage: "lungs.fill"),
                ResusQuickAction(label: "Kejang Berhenti", kind: .seizureStopped, systemImage: "checkmark.seal.fill")
            ]
        }
    }

    // MARK: Mutations

    public mutating func log(_ kind: ResusEventKind, label: String, at date: Date) {
        events.append(ResusEvent(timestamp: date, kind: kind, label: label))
        events.sort { $0.timestamp < $1.timestamp }
        recomputeCycleAnchor()
    }

    /// Removes the most recent intervention (mis-tap correction). Session start/end markers are kept.
    @discardableResult
    public mutating func undoLastIntervention() -> ResusEvent? {
        guard let index = events.lastIndex(where: { $0.kind != .sessionStart && $0.kind != .sessionEnd }) else { return nil }
        let removed = events.remove(at: index)
        recomputeCycleAnchor()
        return removed
    }

    /// The CPR cycle restarts at the chronologically last CPR start / rhythm check / shock; ROSC stops it.
    private mutating func recomputeCycleAnchor() {
        var anchor: Date?
        for event in events {
            switch event.kind {
            case .cprStart, .rhythmCheck, .defibrillation: anchor = event.timestamp
            case .rosc: anchor = nil
            default: break
            }
        }
        cycleStartedAt = anchor
    }

    public mutating func end(at date: Date) {
        guard endedAt == nil else { return }
        endedAt = date
        events.append(ResusEvent(timestamp: date, kind: .sessionEnd, label: "Sesi diakhiri"))
    }

    // MARK: Queries

    public func elapsed(at now: Date) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    /// Seconds remaining in the current 2-minute CPR cycle (nil when no cycle running).
    public func cprCycleRemaining(at now: Date) -> TimeInterval? {
        guard mode == .cardiacArrest, endedAt == nil, let cycleStartedAt else { return nil }
        let inCycle = now.timeIntervalSince(cycleStartedAt).truncatingRemainder(dividingBy: Self.cprCycleSeconds)
        return Self.cprCycleSeconds - max(inCycle, 0)
    }

    /// Number of completed 2-minute cycles since the cycle anchor (used to trigger haptics once per cycle).
    public func completedCycles(at now: Date) -> Int {
        guard let cycleStartedAt else { return 0 }
        return Int(max(0, now.timeIntervalSince(cycleStartedAt)) / Self.cprCycleSeconds)
    }

    public var lastEpinephrine: Date? {
        events.last { $0.kind == .epinephrine }?.timestamp
    }

    /// Seconds until next epinephrine is due (negative = overdue). Nil before the first dose.
    public func epinephrineDueIn(at now: Date) -> TimeInterval? {
        guard mode == .cardiacArrest, endedAt == nil, let last = lastEpinephrine else { return nil }
        return epinephrineInterval - now.timeIntervalSince(last)
    }

    public func count(of kind: ResusEventKind) -> Int { events.filter { $0.kind == kind }.count }

    /// Seizure onset: first “Kejang Dimulai” note if logged, else session start.
    public var seizureOnset: Date {
        events.first { $0.label.hasPrefix("Kejang Dimulai") }?.timestamp ?? startedAt
    }

    public func seizurePhase(at now: Date) -> SeizurePhase {
        let seconds = max(0, (endedAt ?? now).timeIntervalSince(seizureOnset))
        return SeizurePhase.allCases.last { seconds >= $0.startSeconds } ?? .stabilization
    }

    /// Seconds until the next seizure phase boundary (nil in the refractory phase).
    public func secondsToNextSeizurePhase(at now: Date) -> TimeInterval? {
        let seconds = max(0, now.timeIntervalSince(seizureOnset))
        guard let next = SeizurePhase.allCases.first(where: { $0.startSeconds > seconds }) else { return nil }
        return next.startSeconds - seconds
    }

    public static func clock(_ interval: TimeInterval) -> String {
        let total = Int(abs(interval).rounded(.down))
        let sign = interval < 0 ? "-" : ""
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0 ? "\(sign)\(hours):\(pad(minutes)):\(pad(seconds))" : "\(sign)\(pad(minutes)):\(pad(seconds))"
    }
}
