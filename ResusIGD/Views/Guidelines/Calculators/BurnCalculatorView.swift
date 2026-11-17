import SwiftUI
import ClinicalCore

/// Interactive Rule of Nines (%TBSA) selector + Parkland formula with time-of-burn adjustment.
struct BurnCalculatorView: View {
    @State private var model = BurnCalculatorViewModel()

    var body: some View {
        // Re-evaluate every 30 s so "jam sejak kejadian" stays current while the screen is open.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    patientCard
                    tbsaCard
                    timeCard
                    results(now: context.date)
                    DisclaimerFooter()
                }
                .padding(16)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Luka Bakar: TBSA & Parkland")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Selesai") { dismissKeyboard() }
            }
        }
    }

    private var patientCard: some View {
        Card(title: "Pasien", systemImage: "person.fill") {
            HStack(spacing: 12) {
                NumberField(title: "Berat Badan", text: $model.weightText, unit: "kg", prompt: "70")
                NumberField(title: "Usia", text: $model.ageText, unit: "thn", prompt: "30")
            }
            Picker("Formula", selection: $model.formula) {
                ForEach(BurnFormula.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            Toggle("Luka bakar listrik", isOn: $model.isElectrical)
        }
    }

    private var tbsaCard: some View {
        Card(title: "%TBSA — Rule of Nines", systemImage: "figure.stand") {
            Text(model.isChild ? "Proporsi anak (kepala lebih besar, tungkai lebih kecil) sesuai usia." : "Proporsi dewasa. Hanya derajat II–III.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Input %TBSA manual (Lund-Browder / telapak tangan)", isOn: $model.useManualTBSA)
                .font(.subheadline)
            if model.useManualTBSA {
                NumberField(title: "%TBSA", text: $model.manualTBSAText, unit: "%")
            } else {
                ForEach(BurnRegion.allCases) { region in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(region.label).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(ClinicalFormat.number(RuleOfNines.percentage(of: region, ageYears: model.ageYears), maxDecimals: 1))%")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Picker(region.label, selection: Binding(
                            get: { model.fraction(for: region) },
                            set: { model.setFraction($0, for: region) }
                        )) {
                            Text("Tidak").tag(0.0)
                            Text("½ area").tag(0.5)
                            Text("Seluruh").tag(1.0)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            ReadoutTile(title: "Total TBSA", value: ClinicalFormat.number(model.tbsa, maxDecimals: 1), unit: "%", emphasis: true, tint: Theme.warning)
        }
    }

    private var timeCard: some View {
        Card(title: "Waktu Kejadian Luka Bakar", systemImage: "clock.fill") {
            DatePicker("Jam kejadian", selection: $model.burnTime, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            NumberField(title: "Cairan sudah diberikan (pra-RS / rujukan)", text: $model.alreadyGivenText, unit: "mL", prompt: "0")
        }
    }

    @ViewBuilder
    private func results(now: Date) -> some View {
        if let plan = model.plan(now: now) {
            Card(title: "Resusitasi Cairan (Ringer Laktat)", systemImage: "drop.fill", tint: Theme.info) {
                Text("\(ClinicalFormat.number(model.formula.mLPerKgPerPercent)) mL × \(ClinicalFormat.number(model.weightKg ?? 0, maxDecimals: 1)) kg × \(ClinicalFormat.number(model.tbsa, maxDecimals: 1))% = **\(ClinicalFormat.volume(plan.totalML)) mL / 24 jam**")
                    .font(.subheadline)
                Text("Sudah \(ClinicalFormat.number(plan.hoursSinceBurn, maxDecimals: 1)) jam sejak kejadian.")
                    .font(.caption).foregroundStyle(.secondary)

                if plan.remainingFirstPeriodHours > 0 {
                    Text("8 jam pertama — sisa \(ClinicalFormat.number(plan.remainingFirstPeriodHours, maxDecimals: 1)) jam (\(ClinicalFormat.volume(plan.remainingFirstPeriodML)) mL)")
                        .font(.headline)
                    rateRow(plan.firstPeriodRate, emphasis: true)
                }
                Text(plan.remainingFirstPeriodHours > 0 ? "16 jam berikutnya (\(ClinicalFormat.volume(plan.secondHalfML)) mL)" : "Sisa volume hingga 24 jam")
                    .font(.headline)
                rateRow(plan.secondPeriodRate, emphasis: plan.remainingFirstPeriodHours == 0)

                Label("Target urin: \(ClinicalFormat.number(plan.urineOutputTargetML.lowerBound, maxDecimals: 0))\(plan.urineOutputTargetML.upperBound > plan.urineOutputTargetML.lowerBound ? "–\(ClinicalFormat.number(plan.urineOutputTargetML.upperBound, maxDecimals: 0))" : "") mL/jam",
                      systemImage: "drop.triangle")
                    .font(.subheadline.weight(.semibold))
                Text("Formula hanya titik awal — titrasi ±20–30% per jam sesuai produksi urin. Anak < 30 kg: tambahkan cairan rumatan berisi glukosa.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            AlertStack(alerts: plan.alerts)
        } else {
            SafetyBanner(alert: SafetyAlert(.invalidInput, .info, title: "Lengkapi data",
                                            message: "Isi berat badan dan pilih area luka bakar (%TBSA > 0)."))
        }
    }

    private func rateRow(_ rate: RateTriple, emphasis: Bool) -> some View {
        HStack(spacing: 8) {
            ReadoutTile(title: "Pump", value: ClinicalFormat.rate(rate.mLPerHour), unit: "mL/jam", emphasis: emphasis, tint: Theme.info)
            ReadoutTile(title: "Makro", value: ClinicalFormat.drops(rate.macroDropsPerMinute), unit: "tpm")
        }
    }
}
