import SwiftUI
import ClinicalCore

struct PediatricView: View {
    @Environment(ClinicalLibrary.self) private var library
    @State private var model = PediatricViewModel()
    @State private var section: PediatricSection = .resuscitation

    enum PediatricSection: String, CaseIterable, Identifiable {
        case resuscitation = "Resusitasi & Cairan"
        case formulary = "Formularium Obat"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    patientCard
                    weightSummary
                    AlertStack(alerts: model.patientAlerts)
                    Picker("Bagian", selection: $section) {
                        ForEach(PediatricSection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch section {
                    case .resuscitation:
                        equipmentCard
                        fluidCard
                    case .formulary:
                        formulary
                    }
                    DisclaimerFooter()
                }
                .padding(16)
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Pediatri")
            .navigationDestination(for: String.self) { drugID in
                if let drug = model.drugs.first(where: { $0.id == drugID }) {
                    PediatricDrugDetailView(drug: drug, weightKg: model.weightKg, ageMonths: model.ageMonths)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AppearanceMenu() }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Selesai") { dismissKeyboard() }
                }
            }
        }
        .onAppear { model.load(drugs: library.pediatricDrugs) }
        .onChange(of: library.pediatricDrugs) { _, drugs in model.load(drugs: drugs) }
    }

    // MARK: Patient

    private var patientCard: some View {
        Card(title: "Pasien Anak", systemImage: "figure.child") {
            Toggle(isOn: $model.estimationMode.animation()) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BB Tidak Diketahui (Estimasi Emergensi)").font(.subheadline.weight(.bold))
                    Text("Estimasi dari panjang badan atau usia").font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Theme.danger)

            if model.estimationMode {
                Picker("Metode", selection: $model.estimationMethod) {
                    ForEach(WeightEstimationMethod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                Text(model.estimationMethod.formula).font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if !model.estimationMode {
                    NumberField(title: "Berat Badan", text: $model.weightText, unit: "kg", prompt: "12")
                }
                NumberField(title: "Panjang/Tinggi Badan", text: $model.lengthText, unit: "cm", prompt: "85")
            }
            HStack(spacing: 8) {
                NumberField(title: "Usia", text: $model.ageYearsText, unit: "thn")
                NumberField(title: " ", text: $model.ageMonthsText, unit: "bln")
                NumberField(title: " ", text: $model.ageDaysText, unit: "hari")
            }
            Picker("Jenis Kelamin", selection: $model.sex) {
                ForEach(Sex.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var weightSummary: some View {
        if let hint = model.estimationNeedsInput {
            SafetyBanner(alert: SafetyAlert(.invalidInput, .info, title: "Data estimasi belum lengkap", message: hint))
        } else if let weight = model.weightKg {
            HStack(spacing: 10) {
                ReadoutTile(
                    title: model.estimationMode ? "BB Estimasi" : "BB Terukur",
                    value: ClinicalFormat.number(weight, maxDecimals: 1),
                    unit: "kg",
                    emphasis: true,
                    tint: model.estimationMode ? Theme.warning : .accentColor,
                    caption: model.estimate?.note
                )
                if let zone = model.estimate?.zone {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.color(forZone: zone.colorKey))
                            .frame(width: 56, height: 56)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.cardStroke))
                        Text(zone.colorName).font(.caption.weight(.bold))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Zona \(zone.colorName)")
                }
            }
        }
    }

    // MARK: Equipment

    @ViewBuilder
    private var equipmentCard: some View {
        if let e = model.equipment {
            Card(title: "Peralatan Resusitasi", systemImage: "lungs.fill", tint: Theme.danger) {
                if e.ageDerivedFromWeight {
                    Text("Usia tidak diisi — ukuran diturunkan dari BB (± usia \(ClinicalFormat.number(e.ageMonthsUsed / 12, maxDecimals: 1)) thn).")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ReadoutTile(title: "ETT tanpa cuff", value: ClinicalFormat.number(e.ettUncuffedID, maxDecimals: 1), unit: "mm")
                    ReadoutTile(title: "ETT dengan cuff", value: ClinicalFormat.number(e.ettCuffedID, maxDecimals: 1), unit: "mm")
                    ReadoutTile(title: "Kedalaman ETT", value: ClinicalFormat.number(e.ettDepthCm, maxDecimals: 1), unit: "cm", caption: e.ettDepthFormula)
                    ReadoutTile(title: "LMA", value: ClinicalFormat.number(e.lmaSize, maxDecimals: 1), unit: "no.")
                }
                Label(e.laryngoscope, systemImage: "light.max").font(.subheadline.weight(.semibold))
                Text("Siapkan juga ETT 0,5 lebih kecil & lebih besar.").font(.caption).foregroundStyle(.secondary)

                Divider()
                Text("Energi Listrik").font(.headline)
                HStack(spacing: 10) {
                    ReadoutTile(title: "Defibrilasi 1", value: ClinicalFormat.number(e.defibrillationFirstJ), unit: "J", tint: Theme.danger, caption: "2 J/kg")
                    ReadoutTile(title: "Defibrilasi 2+", value: ClinicalFormat.number(e.defibrillationSubsequentJ), unit: "J", tint: Theme.danger, caption: "4 J/kg (maks 10 J/kg / dewasa)")
                }
                HStack(spacing: 10) {
                    ReadoutTile(title: "Kardioversi", value: "\(ClinicalFormat.number(e.cardioversionLowJ))–\(ClinicalFormat.number(e.cardioversionHighJ))", unit: "J", caption: "0,5–1 J/kg (sinkron)")
                    ReadoutTile(title: "Kardioversi ulang", value: ClinicalFormat.number(e.cardioversionEscalationJ), unit: "J", caption: "2 J/kg")
                }

                Divider()
                ReadoutTile(
                    title: "Epinefrin henti jantung (1:10.000)",
                    value: ClinicalFormat.volume(e.epinephrineArrestML), unit: "mL",
                    emphasis: true, tint: Theme.danger,
                    caption: "= \(ClinicalFormat.dose(e.epinephrineArrestMg)) mg IV/IO (0,01 mg/kg, maks 1 mg) tiap 3–5 menit"
                )
            }
        } else {
            Card(title: "Peralatan Resusitasi", systemImage: "lungs.fill") {
                Text("Isi BB atau gunakan mode estimasi untuk menampilkan ukuran alat.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Fluids

    @ViewBuilder
    private var fluidCard: some View {
        if let bolus = model.bolus, let maintenance = model.maintenance {
            Card(title: "Cairan", systemImage: "drop.fill", tint: Theme.info) {
                Picker("Bolus", selection: $model.bolusMLPerKg) {
                    Text("10 mL/kg").tag(10.0)
                    Text("20 mL/kg").tag(20.0)
                }
                .pickerStyle(.segmented)
                ReadoutTile(
                    title: "Bolus kristaloid isotonik",
                    value: ClinicalFormat.volume(bolus.volumeML), unit: "mL",
                    emphasis: true, tint: Theme.info,
                    caption: "NaCl 0,9% / RL dalam 5–20 menit, evaluasi ulang tiap bolus. 10 mL/kg pada neonatus / kelainan jantung."
                )
                AlertStack(alerts: bolus.alerts)
                Text("Rumatan Holliday-Segar").font(.headline)
                HStack(spacing: 10) {
                    ReadoutTile(title: "Per jam (4-2-1)", value: ClinicalFormat.rate(maintenance.hourlyML), unit: "mL/jam", emphasis: true, tint: Theme.info)
                    ReadoutTile(title: "Per 24 jam", value: ClinicalFormat.volume(maintenance.dailyML), unit: "mL")
                }
                HStack(spacing: 10) {
                    ReadoutTile(title: "Makro", value: ClinicalFormat.drops(maintenance.rate.macroDropsPerMinute), unit: "tpm")
                    ReadoutTile(title: "Mikro", value: ClinicalFormat.drops(maintenance.rate.microDropsPerMinute), unit: "tpm")
                }
                Text(maintenance.breakdown).font(.caption).foregroundStyle(.secondary)
                AlertStack(alerts: maintenance.alerts)
            }
        }
    }

    // MARK: Formulary

    private var formulary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Cari obat (mis. parasetamol, ceftriaxone)", text: $model.drugQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(nil, label: "Semua")
                    ForEach(PediatricCategory.allCases) { categoryChip($0, label: $0.label) }
                }
            }

            if model.weightKg == nil {
                SafetyBanner(alert: SafetyAlert(.invalidInput, .info, title: "BB belum diisi", message: "Isi BB (atau aktifkan estimasi) untuk menghitung dosis."))
            }

            ForEach(model.filteredDrugs) { drug in
                NavigationLink(value: drug.id) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(drug.name).font(.headline)
                            Text(drug.category.label + " · " + drug.regimens.map(\.label).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .frame(minHeight: 56)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func categoryChip(_ category: PediatricCategory?, label: String) -> some View {
        let selected = model.categoryFilter == category
        return Button {
            model.categoryFilter = category
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(selected ? Color.accentColor : Theme.card, in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
