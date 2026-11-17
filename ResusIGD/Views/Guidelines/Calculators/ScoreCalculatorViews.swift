import SwiftUI
import ClinicalCore

// MARK: - NIHSS

struct NIHSSCalculatorView: View {
    @State private var selections: [String: ScoreOption] = [:]

    var body: some View {
        let result = NIHSSCalculator.calculate(selections: selections)
        List {
            ForEach(NIHSSCalculator.items) { item in
                Section(item.title) {
                    ForEach(item.options) { option in
                        Button {
                            selections[item.id] = option
                        } label: {
                            HStack {
                                Text(option.label).foregroundStyle(.primary)
                                Spacer()
                                Text(option.isUntestable ? "UN" : "\(option.score)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if selections[item.id] == option {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(result.total)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded)).monospacedDigit()
                VStack(alignment: .leading) {
                    Text("NIHSS / 42").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(result.severity).font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text("\(result.answered)/\(result.itemCount)").font(.caption).foregroundStyle(result.isComplete ? Theme.success : Theme.warning)
                Button("Reset") { selections = [:] }.font(.subheadline)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .navigationTitle("Skor NIHSS")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - GCS

struct GCSCalculatorView: View {
    @State private var variant: GCSVariant = .adult
    @State private var eye = 4
    @State private var verbal = 5
    @State private var motor = 6
    @State private var intubated = false

    var body: some View {
        let items = GCSCalculator.items(for: variant)
        let result = GCSCalculator.calculate(eye: eye, verbal: intubated ? nil : verbal, motor: motor)
        List {
            Section {
                Picker("Varian", selection: $variant) {
                    ForEach(GCSVariant.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Terintubasi (verbal tidak dapat dinilai)", isOn: $intubated)
            }
            scoreSection(items[0], selection: $eye)
            if !intubated { scoreSection(items[1], selection: $verbal) }
            scoreSection(items[2], selection: $motor)
        }
        .safeAreaInset(edge: .top) {
            if let result {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(result.isIntubated ? "\(result.total)T" : "\(result.total)")
                            .font(.system(size: 44, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Theme.color(for: result.severityLevel))
                        Text(result.notation).font(.headline.monospacedDigit())
                        Spacer()
                    }
                    Text(result.severity).font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
        .navigationTitle("Glasgow Coma Scale")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scoreSection(_ item: ScoreItem, selection: Binding<Int>) -> some View {
        Section(item.title) {
            ForEach(item.options) { option in
                Button {
                    selection.wrappedValue = option.score
                } label: {
                    HStack {
                        Text("\(option.score)").font(.headline.monospacedDigit()).frame(width: 28)
                        Text(option.label).foregroundStyle(.primary)
                        Spacer()
                        if selection.wrappedValue == option.score {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Alteplase

struct AlteplaseCalculatorView: View {
    @State private var weightText = ""

    var body: some View {
        let plan = ClinicalFormat.parse(weightText).flatMap(ElectrolyteCalculator.alteplase(weightKg:))
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Alteplase — Stroke Iskemik Akut", systemImage: "brain.head.profile", tint: Theme.color(for: .neurologi)) {
                    NumberField(title: "Berat Badan (aktual/estimasi)", text: $weightText, unit: "kg", prompt: "70")
                    Text("0,9 mg/kg (maks 90 mg) · 10% bolus 1 menit · 90% infus 60 menit · rekonstitusi 1 mg/mL")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let plan {
                    ReadoutTile(title: "Dosis total", value: ClinicalFormat.dose(plan.totalMg), unit: "mg", emphasis: true)
                    HStack(spacing: 10) {
                        ReadoutTile(title: "Bolus (1 menit)", value: ClinicalFormat.dose(plan.bolusMg), unit: "mg",
                                    caption: "= \(ClinicalFormat.volume(plan.bolusML)) mL")
                        ReadoutTile(title: "Infus (60 menit)", value: ClinicalFormat.dose(plan.infusionMg), unit: "mg",
                                    caption: "= \(ClinicalFormat.volume(plan.infusionML)) mL")
                    }
                    ReadoutTile(title: "Laju infus pump", value: ClinicalFormat.rate(plan.infusionRateMLPerHour), unit: "mL/jam", emphasis: true, tint: Theme.success)
                    AlertStack(alerts: plan.alerts)
                    Text("Buang sisa obat di vial di atas dosis total sebelum memulai. Setelah infus selesai, flush selang dengan NaCl 0,9% pada laju yang sama.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                DisclaimerFooter()
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Dosis Alteplase")
        .navigationBarTitleDisplayMode(.inline)
    }
}
