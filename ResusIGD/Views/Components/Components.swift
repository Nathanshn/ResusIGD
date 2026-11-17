import SwiftUI
import UIKit
import ClinicalCore

/// Dismisses the keyboard from anywhere (used by the keyboard toolbar "Selesai" button).
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// MARK: - Card

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    var tint: Color = .primary
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    if let systemImage { Image(systemName: systemImage).foregroundStyle(tint) }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).stroke(Theme.cardStroke))
    }
}

// MARK: - Safety banners

/// Prominent safety alert. Colour + icon + bold title so it is distinguishable from calculated outputs.
struct SafetyBanner: View {
    let alert: SafetyAlert

    var body: some View {
        let color = Theme.color(for: alert.level)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Theme.icon(for: alert.level))
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(alert.level == .danger ? color : .primary)
                Text(alert.message)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(alert.level == .danger ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(color)
                .frame(width: 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alert.level == .danger ? "Bahaya" : alert.level == .warning ? "Peringatan" : "Info"): \(alert.title). \(alert.message)")
    }
}

struct AlertStack: View {
    let alerts: [SafetyAlert]

    var body: some View {
        if !alerts.isEmpty {
            VStack(spacing: 8) {
                ForEach(alerts) { SafetyBanner(alert: $0) }
            }
        }
    }
}

// MARK: - Readouts

/// Large, glanceable numeric output (mL/jam, tpm, mg, mL).
struct ReadoutTile: View {
    let title: String
    let value: String
    let unit: String
    var emphasis: Bool = false
    var tint: Color = .accentColor
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: emphasis ? 48 : 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(emphasis ? tint : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit)
                    .font(emphasis ? .title3.weight(.bold) : .headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(emphasis ? tint.opacity(0.6) : Theme.cardStroke, lineWidth: emphasis ? 2 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

// MARK: - Inputs

/// Decimal text field accepting "," or "." (parsed with `ClinicalFormat.parse`).
struct NumberField: View {
    let title: String
    @Binding var text: String
    var unit: String = ""
    var prompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(prompt, text: $text)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.cardStroke))
        }
    }
}

/// Slider + stepper + exact numeric entry for doses.
struct DoseControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    var usualRange: ClosedRange<Double>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Dosis", value: $value, format: .number.precision(.fractionLength(0...3)))
                    .keyboardType(.decimalPad)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .fixedSize()
                Text(unit).font(.headline).foregroundStyle(.secondary)
                Spacer()
                Stepper("Ubah dosis", value: $value, in: range, step: step)
                    .labelsHidden()
            }
            if range.upperBound > range.lowerBound {
                Slider(value: $value, in: range, step: step)
            }
            HStack {
                Text(ClinicalFormat.dose(range.lowerBound))
                Spacer()
                if let usualRange {
                    Text("Lazim \(ClinicalFormat.dose(usualRange.lowerBound))–\(ClinicalFormat.dose(usualRange.upperBound)) \(unit)")
                        .fontWeight(.semibold)
                }
                Spacer()
                Text(ClinicalFormat.dose(range.upperBound))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// Horizontal chip selector for short option lists.
struct ChipPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let selected = option == selection
                    Button {
                        selection = option
                    } label: {
                        Text(label(option))
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(selected ? Color.accentColor : Theme.card, in: Capsule())
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .overlay(Capsule().stroke(Theme.cardStroke))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// Numbered step list for "Cara Pengenceran & Pemberian".
struct StepList: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.heavy))
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor.opacity(0.15), in: Circle())
                    Text(step)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Floating "Code Blue" button that jumps to the resuscitation timer from any tab.
struct CodeBlueButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "bolt.heart.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Theme.danger, in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .accessibilityLabel("Buka Code Timer")
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }
}

struct DisclaimerFooter: View {
    var body: some View {
        Text("Alat bantu keputusan klinis. Verifikasi setiap dosis dengan formularium RS dan penilaian klinis DPJP.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }
}
