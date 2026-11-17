import SwiftUI
import ClinicalCore

struct GuidelineDetailView: View {
    let guideline: Guideline

    var body: some View {
        let color = Theme.color(for: guideline.category)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(guideline.summary)
                    .font(.subheadline.weight(.semibold))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                if !guideline.calculators.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("KALKULATOR").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                        ForEach(guideline.calculators) { calculator in
                            NavigationLink {
                                EmbeddedCalculatorView(calculator: calculator)
                            } label: {
                                HStack {
                                    Image(systemName: "function").foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(color, in: RoundedRectangle(cornerRadius: 8))
                                    Text(calculator.label).font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(12)
                                .frame(minHeight: 52)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ForEach(guideline.sections) { section in
                    GuidelineSectionView(section: section, accent: color)
                }

                Text("Referensi: " + guideline.references.joined(separator: "; "))
                    .font(.caption2).foregroundStyle(.secondary)
                DisclaimerFooter()
            }
            .padding(16)
            .padding(.bottom, 80)
        }
        .background(Theme.background)
        .navigationTitle(guideline.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GuidelineSectionView: View {
    let section: GuidelineSection
    let accent: Color

    private var style: (icon: String, color: Color) {
        switch section.kind {
        case .targets: ("timer", Theme.info)
        case .checklist: ("checklist", accent)
        case .drugs: ("pills.fill", Theme.success)
        case .redFlags: ("exclamationmark.octagon.fill", Theme.danger)
        case .notes: ("note.text", .secondary)
        case .table: ("tablecells", accent)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(section.title, systemImage: style.icon)
                .font(.headline)
                .foregroundStyle(section.kind == .redFlags ? Theme.danger : .primary)
            switch section.kind {
            case .checklist:
                ChecklistView(items: section.items, tint: style.color)
            case .table:
                TableSectionView(rows: section.items)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(style.color).frame(width: 7, height: 7).padding(.top, 6)
                            Text(item)
                                .font(section.kind == .targets ? .subheadline.weight(.semibold) : .subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(section.kind == .redFlags ? Theme.danger.opacity(0.10) : Theme.card,
                    in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Tappable checklist — ticks are kept only while the screen is open (bedside use).
private struct ChecklistView: View {
    let items: [String]
    let tint: Color
    @State private var done: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    if done.contains(index) { done.remove(index) } else { done.insert(index) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: done.contains(index) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(done.contains(index) ? Theme.success : tint)
                        Text(item)
                            .font(.subheadline)
                            .strikethrough(done.contains(index))
                            .foregroundStyle(done.contains(index) ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct TableSectionView: View {
    let rows: [String]

    var body: some View {
        let cells = rows.map { $0.components(separatedBy: " | ") }
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            Text(cell)
                                .font(index == 0 || column == 0 ? .caption.weight(.bold) : .caption)
                                .frame(minWidth: column == 0 ? 96 : 70, alignment: .leading)
                        }
                    }
                    if index == 0 { Divider() }
                }
            }
        }
    }
}

/// Routes an `EmbeddedCalculator` to its interactive view.
struct EmbeddedCalculatorView: View {
    let calculator: EmbeddedCalculator

    var body: some View {
        switch calculator {
        case .burnParkland: BurnCalculatorView()
        case .nihss: NIHSSCalculatorView()
        case .alteplase: AlteplaseCalculatorView()
        case .gcs: GCSCalculatorView()
        case .sodiumCorrection: SodiumCorrectionView()
        case .potassiumDrip: PotassiumDripView()
        }
    }
}
