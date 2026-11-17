import SwiftUI
import ClinicalCore

struct PediatricDrugDetailView: View {
    let weightKg: Double?
    let ageMonths: Double?
    @State private var model: PediatricDoseViewModel

    init(drug: PediatricDrug, weightKg: Double?, ageMonths: Double?) {
        self.weightKg = weightKg
        self.ageMonths = ageMonths
        _model = State(initialValue: PediatricDoseViewModel(drug: drug))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                patientStrip
                selectors
                if let regimen = model.regimen, !regimen.isWeightBanded, let range = model.mgPerKgRange {
                    Card(title: "Dosis per kg", systemImage: "scalemass.fill") {
                        DoseControl(
                            value: $model.mgPerKg,
                            range: range,
                            step: model.mgPerKgStep,
                            unit: "mg/kg",
                            usualRange: regimen.mgPerKgMin.flatMap { low in regimen.mgPerKgMax.map { low...$0 } }
                        )
                    }
                }
                resultSection
                warnings
                monograph
                DisclaimerFooter()
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle(model.drug.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var patientStrip: some View {
        HStack {
            Label(weightKg.map { "\(ClinicalFormat.number($0, maxDecimals: 1)) kg" } ?? "BB belum diisi", systemImage: "scalemass")
            Spacer()
            if let ageMonths {
                Label(ageMonths >= 24 ? "\(ClinicalFormat.number(ageMonths / 12, maxDecimals: 1)) thn" : "\(ClinicalFormat.number(ageMonths, maxDecimals: 0)) bln",
                      systemImage: "calendar")
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var selectors: some View {
        Card(title: "Regimen & Sediaan", systemImage: "pills.fill") {
            Picker("Regimen", selection: Binding(get: { model.regimen?.id ?? "" }, set: { model.selectRegimen($0) })) {
                ForEach(model.drug.regimens) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.menu)
            if let regimen = model.regimen {
                Text(regimen.indication).font(.footnote).foregroundStyle(.secondary)
            }
            Text("Sediaan tersedia").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(model.formulations) { formulation in
                    let selected = formulation.id == model.formulation?.id
                    Button {
                        model.selectFormulation(formulation.id)
                    } label: {
                        HStack {
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selected ? Color.accentColor : .secondary)
                            Text(formulation.label).font(.subheadline.weight(selected ? .bold : .regular))
                            Spacer()
                        }
                        .padding(10)
                        .frame(minHeight: 44)
                        .background(selected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let result = model.result(weightKg: weightKg, ageMonths: ageMonths) {
            if result.isValid {
                HStack(spacing: 10) {
                    ReadoutTile(
                        title: "Dosis",
                        value: ClinicalFormat.dose(result.doseMg), unit: "mg",
                        emphasis: true,
                        caption: "\(ClinicalFormat.dose(result.mgPerKgActual)) mg/kg"
                    )
                    if let volume = result.volumeML {
                        ReadoutTile(title: "Volume", value: ClinicalFormat.volume(volume), unit: "mL", emphasis: true, tint: Theme.success,
                                    caption: model.formulation?.label)
                    } else if let units = result.units {
                        ReadoutTile(title: "Jumlah", value: ClinicalFormat.number(units, maxDecimals: 2), unit: result.unitName ?? "unit",
                                    emphasis: true, tint: Theme.success, caption: model.formulation?.label)
                    }
                }
                if result.isCapped {
                    Label("Dosis dibatasi — hasil hitung \(ClinicalFormat.dose(result.targetDoseMg)) mg", systemImage: "hand.raised.fill")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Theme.warning)
                }
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(result.route.label) · \(result.frequency)", systemImage: "clock")
                            .font(.subheadline.weight(.semibold))
                        if let daily = result.dailyDoseMg {
                            Text("Total harian: \(ClinicalFormat.dose(daily)) mg/24 jam").font(.footnote)
                        }
                        Text(result.administration).font(.footnote)
                    }
                }
            }
            AlertStack(alerts: result.alerts)
        } else {
            SafetyBanner(alert: SafetyAlert(.invalidInput, .info, title: "BB belum diisi",
                                            message: "Kembali ke layar Pediatri dan isi BB atau aktifkan estimasi BB."))
        }
    }

    @ViewBuilder
    private var warnings: some View {
        let notes = (model.regimen?.notes ?? []) + model.drug.warnings
        if !notes.isEmpty {
            Card(title: "Perhatian", systemImage: "exclamationmark.triangle.fill", tint: Theme.warning) {
                ForEach(notes, id: \.self) { Text("• \($0)").font(.footnote) }
            }
        }
    }

    private var monograph: some View {
        Card {
            DisclosureGroup("Monografi") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.drug.monograph).font(.subheadline)
                    Text("Referensi: " + model.drug.references.joined(separator: "; ")).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }
}
