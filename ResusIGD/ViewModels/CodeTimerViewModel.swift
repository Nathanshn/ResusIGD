import Foundation
import Observation
import SwiftData
import UIKit
import AudioToolbox
import ClinicalCore

/// Module 4 — resuscitation timer & one-tap logger. Timing logic lives in `ResusSessionEngine`;
/// this view model only drives the clock, cues (haptic/audio), persistence and clipboard export.
@MainActor
@Observable
final class CodeTimerViewModel {
    private(set) var session: ResusSessionEngine?
    private(set) var now = Date()
    /// Incremented whenever a cue fires — drives `.sensoryFeedback`.
    private(set) var cueTrigger = 0
    private(set) var lastCue: String?
    var copiedConfirmation = false

    // Setup
    var mode: ResusMode = .cardiacArrest
    var epinephrineInterval: TimeInterval = 240
    var patientInfo = ""
    var soundEnabled = true

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var record: ResusSessionRecord?
    @ObservationIgnored private var lastCycleCount = 0
    @ObservationIgnored private var epinephrineCueFired = false
    @ObservationIgnored private var lastPhase: SeizurePhase?

    var isActive: Bool { session != nil && session?.endedAt == nil }

    // MARK: Lifecycle

    func attach(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        restoreActiveSession()
    }

    /// Resumes an unfinished session (e.g. app was killed during a code).
    private func restoreActiveSession() {
        guard let context else { return }
        var descriptor = FetchDescriptor<ResusSessionRecord>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let active = try? context.fetch(descriptor).first, let engine = active.engine else { return }
        record = active
        session = engine
        mode = engine.mode
        epinephrineInterval = engine.epinephrineInterval
        patientInfo = active.patientInfo
        resetCueTrackers()
        setScreenAwake(true)
    }

    func start() {
        let engine = ResusSessionEngine(mode: mode, startedAt: Date(), epinephrineInterval: epinephrineInterval)
        let newRecord = ResusSessionRecord(engine: engine, patientInfo: patientInfo)
        context?.insert(newRecord)
        record = newRecord
        session = engine
        now = Date()
        resetCueTrackers()
        persist()
        setScreenAwake(true)
    }

    func log(_ action: ResusQuickAction) {
        guard var engine = session, engine.endedAt == nil else { return }
        let date = Date()
        engine.log(action.kind, label: action.label, at: date)
        session = engine
        now = date
        if action.kind == .epinephrine { epinephrineCueFired = false }
        lastCycleCount = engine.completedCycles(at: date)
        persist()
    }

    func undoLast() {
        guard var engine = session else { return }
        engine.undoLastIntervention()
        session = engine
        lastCycleCount = engine.completedCycles(at: Date())
        persist()
    }

    func updateEpinephrineInterval(_ interval: TimeInterval) {
        epinephrineInterval = interval
        guard var engine = session else { return }
        engine.epinephrineInterval = interval
        session = engine
        persist()
    }

    func end() {
        guard var engine = session else { return }
        engine.end(at: Date())
        session = engine
        persist()
        setScreenAwake(false)
    }

    func newSession() {
        if isActive { end() }
        session = nil
        record = nil
        patientInfo = ""
        lastCue = nil
    }

    // MARK: Clock & cues

    func tick() {
        now = Date()
        guard let engine = session, engine.endedAt == nil else { return }
        switch engine.mode {
        case .cardiacArrest:
            let cycles = engine.completedCycles(at: now)
            if engine.cycleStartedAt != nil && cycles > lastCycleCount {
                lastCycleCount = cycles
                cue("Siklus RJP 2 menit selesai — cek irama, ganti kompresor")
            }
            if let due = engine.epinephrineDueIn(at: now), due <= 0, !epinephrineCueFired {
                epinephrineCueFired = true
                cue("Waktunya epinefrin 1 mg IV")
            }
        case .statusEpilepticus:
            let phase = engine.seizurePhase(at: now)
            if let lastPhase, phase != lastPhase {
                cue("Masuk fase \(phase.label)")
            }
            lastPhase = phase
        }
    }

    private func cue(_ message: String) {
        lastCue = message
        cueTrigger += 1
        if soundEnabled { AudioServicesPlaySystemSound(1005) }
    }

    private func resetCueTrackers() {
        lastCycleCount = session?.completedCycles(at: Date()) ?? 0
        epinephrineCueFired = false
        lastPhase = session?.seizurePhase(at: Date())
    }

    // MARK: Export

    func soapText() -> String {
        guard let session else { return "" }
        return SOAPLogFormatter.format(session: session, now: Date(), patientInfo: patientInfo)
    }

    func copySOAPToClipboard() {
        UIPasteboard.general.string = soapText()
        copiedConfirmation = true
    }

    // MARK: Persistence

    private func persist() {
        guard let session, let record else { return }
        record.update(with: session)
        record.patientInfo = patientInfo
        try? context?.save()
    }

    func savePatientInfo() { persist() }

    private func setScreenAwake(_ awake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = awake
    }
}
