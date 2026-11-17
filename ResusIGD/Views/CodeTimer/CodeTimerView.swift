import SwiftUI
import SwiftData
import UIKit
import ClinicalCore

struct CodeTimerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = CodeTimerViewModel()
    @State private var confirmEnd = false
    @State private var showSOAP = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let session = model.session {
                        header(session)
                        if session.mode == .cardiacArrest {
                            cardiacPanel(session)
                        } else {
                            seizurePanel(session)
                        }
                        if session.endedAt == nil { actionGrid(session.mode) }
                        logList(session)
                        controls(session)
                    } else {
                        setupCard
                        SessionHistoryView()
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Code Timer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.soundEnabled.toggle()
                    } label: {
                        Image(systemName: model.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    .accessibilityLabel(model.soundEnabled ? "Matikan suara" : "Nyalakan suara")
                }
                ToolbarItem(placement: .topBarTrailing) { AppearanceMenu() }
            }
            .sheet(isPresented: $showSOAP) { soapSheet }
        }
        .sensoryFeedback(.warning, trigger: model.cueTrigger)
        .onAppear { model.attach(context: modelContext) }
        .task {
            while !Task.isCancelled {
                model.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .confirmationDialog("Akhiri sesi resusitasi?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Akhiri Sesi", role: .destructive) { model.end() }
            Button("Batal", role: .cancel) {}
        }
    }

    // MARK: Setup

    private var setupCard: some View {
        Card(title: "Mulai Sesi", systemImage: "play.circle.fill", tint: Theme.danger) {
            Picker("Mode", selection: $model.mode) {
                ForEach(ResusMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if model.mode == .cardiacArrest {
                epinephrineIntervalPicker
            }
            TextField("Identitas pasien (opsional): inisial, usia, no. RM", text: $model.patientInfo)
                .padding(12)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
            Button {
                model.start()
            } label: {
                Label(model.mode == .cardiacArrest ? "MULAI CODE BLUE" : "MULAI TIMER KEJANG", systemImage: "bolt.heart.fill")
                    .font(.title3.weight(.heavy))
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.danger)
            Text("Waktu dihitung dari jam perangkat dan tetap tersimpan bila aplikasi tertutup.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var epinephrineIntervalPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pengingat epinefrin").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("Pengingat epinefrin", selection: Binding(get: { model.epinephrineInterval }, set: { model.updateEpinephrineInterval($0) })) {
                ForEach(ResusSessionEngine.epinephrineIntervalOptions, id: \.self) { seconds in
                    Text("\(Int(seconds / 60)) menit").tag(seconds)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Active session

    private func header(_ session: ResusSessionEngine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.mode.label.uppercased()).font(.caption.weight(.heavy)).foregroundStyle(Theme.danger)
                Spacer()
                if session.endedAt != nil {
                    Text("SELESAI").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                }
            }
            Text(ResusSessionEngine.clock(session.elapsed(at: model.now)))
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Durasi \(ResusSessionEngine.clock(session.elapsed(at: model.now)))")
            if let cue = model.lastCue, session.endedAt == nil {
                Label(cue, systemImage: "bell.badge.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    private func cardiacPanel(_ session: ResusSessionEngine) -> some View {
        HStack(spacing: 12) {
            // 2-minute CPR cycle ring
            VStack(spacing: 6) {
                let remaining = session.cprCycleRemaining(at: model.now)
                ZStack {
                    Circle().stroke(Theme.card, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat((remaining ?? 0) / ResusSessionEngine.cprCycleSeconds))
                        .stroke((remaining ?? 120) <= 15 ? Theme.danger : Theme.info, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: remaining)
                    VStack(spacing: 0) {
                        Text(remaining.map(ResusSessionEngine.clock) ?? "--:--")
                            .font(.title.weight(.heavy)).monospacedDigit()
                        Text("Siklus RJP").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 140, height: 140)
                if remaining == nil {
                    Text("Tap \"RJP Dimulai\"").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                epinephrineStatus(session)
                Text("Epinefrin: \(session.count(of: .epinephrine))×").font(.subheadline.weight(.semibold))
                Text("Defibrilasi: \(session.count(of: .defibrillation))×").font(.subheadline.weight(.semibold))
                Text("Amiodaron: \(session.count(of: .amiodarone))×").font(.subheadline.weight(.semibold))
                if session.endedAt == nil {
                    epinephrineIntervalPicker
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func epinephrineStatus(_ session: ResusSessionEngine) -> some View {
        if let due = session.epinephrineDueIn(at: model.now) {
            let overdue = due <= 0
            VStack(alignment: .leading, spacing: 2) {
                Text(overdue ? "WAKTUNYA EPINEFRIN" : "Epinefrin berikutnya")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(overdue ? Theme.danger : .secondary)
                Text(overdue ? "+" + ResusSessionEngine.clock(-due) : ResusSessionEngine.clock(due))
                    .font(.title2.weight(.heavy)).monospacedDigit()
                    .foregroundStyle(overdue ? Theme.danger : .primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((overdue ? Theme.danger : Theme.card).opacity(overdue ? 0.18 : 1), in: RoundedRectangle(cornerRadius: 10))
        } else if session.endedAt == nil {
            Text("Epinefrin belum diberikan").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private func seizurePanel(_ session: ResusSessionEngine) -> some View {
        let phase = session.seizurePhase(at: model.now)
        let color: Color = phase >= .secondTherapy ? Theme.danger : (phase == .initialTherapy ? Theme.warning : Theme.info)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(SeizurePhase.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item <= phase ? color : Theme.card)
                        .frame(height: 8)
                }
            }
            Text(phase.label).font(.title3.weight(.heavy)).foregroundStyle(color)
            Text(phase.action).font(.subheadline)
            if let next = session.secondsToNextSeizurePhase(at: model.now), session.endedAt == nil {
                Text("Fase berikutnya dalam \(ResusSessionEngine.clock(next))")
                    .font(.headline.monospacedDigit())
            }
            Text("Durasi kejang dihitung dari tombol \"Kejang Dimulai (onset)\" bila ditekan, atau dari awal sesi.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func actionGrid(_ mode: ResusMode) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(ResusSessionEngine.quickActions(for: mode)) { action in
                Button {
                    model.log(action)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: action.systemImage).font(.title2.weight(.bold))
                        Text(action.label)
                            .font(.subheadline.weight(.heavy))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                }
                .buttonStyle(.borderedProminent)
                .tint(actionColor(for: action.kind))
                .sensoryFeedback(.impact(weight: .heavy), trigger: model.session?.events.count ?? 0)
            }
        }
    }

    private func actionColor(for kind: ResusEventKind) -> Color {
        switch kind {
        case .epinephrine, .benzodiazepine: Theme.danger
        case .defibrillation: Theme.warning
        case .rosc, .seizureStopped: Theme.success
        case .amiodarone, .secondLineAntiseizure: Color(uiColor: .systemPurple)
        default: Theme.info
        }
    }

    private func logList(_ session: ResusSessionEngine) -> some View {
        Card(title: "Log Tindakan", systemImage: "list.bullet.clipboard") {
            let events = session.events.reversed()
            ForEach(Array(events), id: \.id) { event in
                HStack(alignment: .firstTextBaseline) {
                    Text(event.timestamp, format: .dateTime.hour().minute().second())
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text("+" + ResusSessionEngine.clock(event.timestamp.timeIntervalSince(session.startedAt)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(event.label).font(.subheadline)
                    Spacer()
                }
            }
        }
    }

    private func controls(_ session: ResusSessionEngine) -> some View {
        VStack(spacing: 10) {
            TextField("Identitas pasien (opsional)", text: $model.patientInfo)
                .onSubmit { model.savePatientInfo() }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            Button {
                model.copySOAPToClipboard()
            } label: {
                Label(model.copiedConfirmation ? "Tersalin ✓" : "Salin Log ke Clipboard (Format SOAP)", systemImage: "doc.on.clipboard")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .sensoryFeedback(.success, trigger: model.copiedConfirmation)
            Button("Pratinjau SOAP") { showSOAP = true }
            HStack(spacing: 10) {
                if session.endedAt == nil {
                    Button {
                        model.undoLast()
                    } label: {
                        Label("Batalkan terakhir", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) {
                        confirmEnd = true
                    } label: {
                        Label("Akhiri Sesi", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        model.newSession()
                    } label: {
                        Label("Sesi Baru", systemImage: "plus.circle.fill").frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onChange(of: model.copiedConfirmation) { _, copied in
            guard copied else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                model.copiedConfirmation = false
            }
        }
    }

    private var soapSheet: some View {
        NavigationStack {
            ScrollView {
                Text(model.soapText())
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .navigationTitle("Log SOAP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salin") { model.copySOAPToClipboard(); showSOAP = false }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { showSOAP = false }
                }
            }
        }
    }
}

/// Previously completed sessions (stored locally) with one-tap SOAP copy.
private struct SessionHistoryView: View {
    @Query(filter: #Predicate<ResusSessionRecord> { $0.endedAt != nil },
           sort: \ResusSessionRecord.startedAt, order: .reverse)
    private var records: [ResusSessionRecord]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if !records.isEmpty {
            Card(title: "Riwayat Sesi (perangkat ini)", systemImage: "clock.arrow.circlepath") {
                ForEach(records.prefix(10)) { record in
                    if let engine = record.engine {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(engine.mode.label).font(.subheadline.weight(.semibold))
                                Text(record.startedAt, format: .dateTime.day().month().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                UIPasteboard.general.string = SOAPLogFormatter.format(session: engine, now: Date(), patientInfo: record.patientInfo)
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                            }
                            .accessibilityLabel("Salin SOAP")
                            Button(role: .destructive) {
                                modelContext.delete(record)
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Hapus sesi")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}
