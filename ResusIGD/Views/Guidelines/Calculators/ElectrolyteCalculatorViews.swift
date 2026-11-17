import SwiftUI
import ClinicalCore

struct SodiumCorrectionView: View {
    @State private var model = ElectrolyteViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Hiponatremia — Adrogué-Madias", systemImage: "drop.fill", tint: Theme.color(for: .metabolik)) {
                    HStack(spacing: 12) {
                        NumberField(title: "Na serum", text: $model.sodiumText, unit: "mmol/L", prompt: "118")
                        NumberField(title: "Berat Badan", text: $model.weightText, unit: "kg", prompt: "60")
                    }
                    HStack(spacing: 12) {
                        NumberField(title: "Usia", text: $model.ageText, unit: "thn", prompt: "50")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Jenis kelamin").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Picker("Jenis kelamin", selection: $model.sex) {
                                ForEach(Sex.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    Picker("Cairan", selection: $model.infusate) {
                        ForEach(SodiumInfusate.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Toggle("Risiko tinggi ODS (batas 8 mmol/L/24 jam)", isOn: $model.highODSRisk)
                        .font(.subheadline)
                }

                if let plan = model.sodiumPlan {
                    HStack(spacing: 10) {
                        ReadoutTile(title: "Target 24 jam", value: ClinicalFormat.number(plan.targetSodium, maxDecimals: 1), unit: "mmol/L")
                        ReadoutTile(title: "Defisit Na", value: ClinicalFormat.number(plan.deficitMmol, maxDecimals: 0), unit: "mmol",
                                    caption: "TBW \(ClinicalFormat.number(plan.totalBodyWaterL, maxDecimals: 1)) L (× \(ClinicalFormat.number(plan.tbwFactor, maxDecimals: 2)))")
                    }
                    if plan.volumeML > 0 {
                        ReadoutTile(title: "Volume cairan / 24 jam", value: ClinicalFormat.volume(plan.volumeML), unit: "mL", emphasis: true,
                                    caption: "Δ Na per 1 L = \(ClinicalFormat.number(plan.changePerLiter, maxDecimals: 2)) mmol/L")
                        HStack(spacing: 10) {
                            ReadoutTile(title: "Pump", value: ClinicalFormat.rate(plan.rate.mLPerHour), unit: "mL/jam", emphasis: true, tint: Theme.success)
                            ReadoutTile(title: "Mikro", value: ClinicalFormat.drops(plan.rate.microDropsPerMinute), unit: "tpm")
                        }
                    }
                    AlertStack(alerts: plan.alerts)
                }
                DisclaimerFooter()
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Koreksi Hiponatremia")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PotassiumDripView: View {
    @State private var model = ElectrolyteViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Drip KCl", systemImage: "bolt.fill", tint: Theme.color(for: .metabolik)) {
                    HStack(spacing: 12) {
                        NumberField(title: "K serum", text: $model.potassiumText, unit: "mEq/L", prompt: "2,8")
                        NumberField(title: "Berat Badan", text: $model.weightText, unit: "kg", prompt: "60")
                    }
                    NumberField(title: "Usia", text: $model.ageText, unit: "thn", prompt: "50")
                    HStack(spacing: 12) {
                        NumberField(title: "KCl total", text: $model.kclTotalText, unit: "mEq")
                        NumberField(title: "Dalam volume", text: $model.kclVolumeText, unit: "mL")
                    }
                    NumberField(title: "Laju KCl", text: $model.kclRateText, unit: "mEq/jam")
                    Picker("Akses", selection: $model.access) {
                        ForEach(VascularAccess.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("KCl 7,46% = 1 mEq/mL (25 mL = 25 mEq). JANGAN bolus/IV push.")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.danger)
                }

                if let plan = model.potassiumPlan {
                    ReadoutTile(title: "Laju pump", value: ClinicalFormat.rate(plan.rate.mLPerHour), unit: "mL/jam", emphasis: true,
                                caption: "Habis dalam ±\(ClinicalFormat.number(plan.durationHours, maxDecimals: 1)) jam")
                    HStack(spacing: 10) {
                        ReadoutTile(title: "Makro", value: ClinicalFormat.drops(plan.rate.macroDropsPerMinute), unit: "tpm")
                        ReadoutTile(title: "Konsentrasi", value: ClinicalFormat.number(plan.concentrationMEqPerL, maxDecimals: 0), unit: "mEq/L")
                    }
                    HStack(spacing: 10) {
                        ReadoutTile(title: "Batas laju", value: ClinicalFormat.number(plan.maxRateMEqPerHour, maxDecimals: 1), unit: "mEq/jam")
                        ReadoutTile(title: "Perkiraan ↑K", value: "+" + ClinicalFormat.number(plan.expectedRise, maxDecimals: 1), unit: "mEq/L",
                                    caption: "±0,1 per 10 mEq (bervariasi)")
                    }
                    AlertStack(alerts: plan.alerts)
                } else {
                    SafetyBanner(alert: SafetyAlert(.invalidInput, .info, title: "Lengkapi data", message: "Isi BB, jumlah KCl, volume, dan laju."))
                }
                DisclaimerFooter()
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Drip KCl")
        .navigationBarTitleDisplayMode(.inline)
    }
}
