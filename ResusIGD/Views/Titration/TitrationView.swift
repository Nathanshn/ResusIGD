import SwiftUI
import ClinicalCore

struct TitrationView: View {
    @Environment(ClinicalLibrary.self) private var library
    @State private var model = TitrationViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    patientCard
                    drugPicker
                    if let regimen = model.regimen {
                        doseCard(regimen)
                        if model.isBolus { bolusOutputs } else { infusionOutputs }
                        AlertStack(alerts: model.alerts)
                        if !model.isBolus { preparationCard }
                        stepsCard
                        monographCard
                    }
                    DisclaimerFooter()
                }
                .padding(16)
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Titrasi Dewasa")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AppearanceMenu() }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Selesai") { dismissKeyboard() }
                }
            }
        }
        .onAppear { model.load(drugs: library.adultDrugs) }
        .onChange(of: library.adultDrugs) { _, drugs in model.load(drugs: drugs) }
    }

    // MARK: Sections

    private var patientCard: some View {
        Card(title: "Pasien", systemImage: "person.fill") {
            HStack(spacing: 12) {
                NumberField(title: "Berat Badan", text: $model.weightText, unit: "kg", prompt: "70")
                NumberField(title: "Usia", text: $model.ageText, unit: "thn", prompt: "45")
            }
            Picker("Jenis Kelamin", selection: $model.sex) {
                ForEach(Sex.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var drugPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChipPicker(
                options: model.drugs.map(\.id),
                selection: Binding(get: { model.selectedDrugID ?? "" }, set: { model.selectDrug($0) }),
                label: { id in model.drugs.first { $0.id == id }?.name ?? id }
            )
            if let drug = model.drug {
                HStack(spacing: 6) {
                    if drug.isHighAlert {
                        Text("HIGH ALERT")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Theme.highAlert, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Text(drug.drugClass).font(.caption).foregroundStyle(.secondary)
                }
                if drug.regimens.count > 1 {
                    Picker("Regimen", selection: Binding(get: { model.selectedRegimenID ?? "" }, set: { model.selectRegimen($0) })) {
                        ForEach(drug.regimens) { Text($0.label).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .font(.headline)
                }
            }
        }
    }

    private func doseCard(_ regimen: AdultRegimen) -> some View {
        Card(title: regimen.mode == .bolus ? "Dosis Bolus" : "Dosis Titrasi", systemImage: "dial.medium.fill", tint: .accentColor) {
            Text(regimen.indication).font(.footnote).foregroundStyle(.secondary)
            DoseControl(
                value: $model.dose,
                range: model.doseRange,
                step: regimen.step,
                unit: regimen.doseUnitLabel,
                usualRange: model.usualRange
            )
        }
    }

    @ViewBuilder
    private var infusionOutputs: some View {
        if let result = model.infusionResult {
            let valid = result.isValid
            VStack(spacing: 10) {
                ReadoutTile(
                    title: model.finalVolumeML <= 60 ? "Syringe Pump" : "Infusion Pump",
                    value: valid ? ClinicalFormat.rate(result.rateMLPerHour) : "–",
                    unit: "mL/jam",
                    emphasis: true,
                    caption: valid ? "= cc/jam · 1 sediaan ±\(ClinicalFormat.number(result.hoursPerPreparation ?? 0, maxDecimals: 1)) jam" : nil
                )
                HStack(spacing: 10) {
                    ReadoutTile(title: "Makro (20 tts/mL)", value: valid ? ClinicalFormat.drops(result.macroDropsPerMinute) : "–", unit: "tpm")
                    ReadoutTile(title: "Mikro (60 tts/mL)", value: valid ? ClinicalFormat.drops(result.microDropsPerMinute) : "–", unit: "tpm")
                }
                ReadoutTile(
                    title: "Konsentrasi Larutan",
                    value: ClinicalFormat.dose(result.concentrationDisplayValue),
                    unit: result.concentrationDisplayUnit.label,
                    caption: "\(ClinicalFormat.dose(result.totalDrugMg)) mg dalam \(ClinicalFormat.volume(model.finalVolumeML)) mL \(model.diluent.shortLabel)"
                )
            }
        }
    }

    @ViewBuilder
    private var bolusOutputs: some View {
        if let result = model.bolusResult {
            HStack(spacing: 10) {
                ReadoutTile(title: "Dosis", value: ClinicalFormat.dose(result.doseMg), unit: "mg", emphasis: true)
                ReadoutTile(title: "Volume", value: result.isValid ? ClinicalFormat.volume(result.undilutedVolumeML) : "–", unit: "mL", emphasis: true, tint: Theme.success)
            }
            ReadoutTile(title: "Jumlah Ampul", value: ClinicalFormat.number(result.ampoulesNeeded, maxDecimals: 2), unit: "ampul",
                        caption: "Sediaan \(AmpouleStrength(mg: model.ampouleMg, mL: model.ampouleML).label)")
        }
    }

    private var preparationCard: some View {
        Card(title: "Sediaan & Pengenceran", systemImage: "flask.fill") {
            HStack(spacing: 12) {
                labeledValueField("Kekuatan ampul (mg)", value: $model.ampouleMg)
                labeledValueField("Volume ampul (mL)", value: $model.ampouleML)
            }
            if model.isCustomAmpoule {
                Button("Kembalikan sediaan standar") { model.resetPreparation() }
                    .font(.footnote)
            }
            Stepper(value: $model.ampouleCount, in: 0.5...50, step: 0.5) {
                Text("Jumlah ampul: **\(ClinicalFormat.number(model.ampouleCount, maxDecimals: 1))**")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Volume akhir").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Volume akhir", selection: $model.finalVolumeML) {
                    ForEach(InfusionCalculator.standardFinalVolumes, id: \.self) { volume in
                        Text("\(ClinicalFormat.number(volume)) mL").tag(volume)
                    }
                }
                .pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Pelarut").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Pelarut", selection: $model.diluent) {
                    ForEach(Diluent.allCases) { Text($0.shortLabel).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Akses vena").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Akses vena", selection: $model.access) {
                    ForEach(VascularAccess.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private var stepsCard: some View {
        let steps = model.isBolus ? (model.bolusResult?.steps ?? []) : (model.infusionResult?.preparationSteps ?? [])
        if !steps.isEmpty {
            Card(title: "Cara Pengenceran & Pemberian", systemImage: "list.number") {
                StepList(steps: steps)
            }
        }
    }

    @ViewBuilder
    private var monographCard: some View {
        if let drug = model.drug {
            Card {
                DisclosureGroup("Monografi \(drug.name)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(drug.monograph).font(.subheadline)
                        ForEach(drug.diluentRules, id: \.diluent) { rule in
                            Text("• \(rule.diluent.shortLabel): \(rule.note)").font(.footnote)
                        }
                        Text("Referensi: " + drug.references.joined(separator: "; "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private func labeledValueField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...3)))
                .keyboardType(.decimalPad)
                .font(.headline)
                .monospacedDigit()
                    .padding(10)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
