import SwiftUI
import ClinicalCore

/// User-selectable appearance. "Gelap (OLED)" uses pure black backgrounds for night shifts.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Ikuti Sistem"
        case .light: "Terang"
        case .dark: "Gelap (OLED)"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Theme {
    /// `systemBackground` is pure black (#000) in dark mode → OLED friendly.
    static let background = Color(uiColor: .systemBackground)
    static let card = Color(uiColor: .secondarySystemBackground)
    static let cardStroke = Color.primary.opacity(0.08)
    static let accent = Color.accentColor

    static let danger = Color(uiColor: .systemRed)
    static let warning = Color(uiColor: .systemOrange)
    static let info = Color(uiColor: .systemBlue)
    static let success = Color(uiColor: .systemGreen)
    static let highAlert = Color(uiColor: .systemPink)

    static let cornerRadius: CGFloat = 16

    static func color(for level: AlertLevel) -> Color {
        switch level {
        case .danger: danger
        case .warning: warning
        case .info: info
        }
    }

    static func icon(for level: AlertLevel) -> String {
        switch level {
        case .danger: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    static func color(for category: GuidelineCategory) -> Color {
        switch category {
        case .kardiologi: Color(uiColor: .systemRed)
        case .neurologi: Color(uiColor: .systemPurple)
        case .trauma: Color(uiColor: .systemOrange)
        case .alergiImunologi: Color(uiColor: .systemPink)
        case .metabolik: Color(uiColor: .systemTeal)
        case .umum: Color(uiColor: .systemGray)
        }
    }

    static func icon(for category: GuidelineCategory) -> String {
        switch category {
        case .kardiologi: "heart.fill"
        case .neurologi: "brain.head.profile"
        case .trauma: "bandage.fill"
        case .alergiImunologi: "allergens"
        case .metabolik: "drop.fill"
        case .umum: "stethoscope"
        }
    }

    static func color(forZone key: String) -> Color {
        switch key {
        case "grey": .gray
        case "pink": .pink
        case "red": .red
        case "purple": .purple
        case "yellow": .yellow
        case "white": Color(uiColor: .systemGray5)
        case "blue": .blue
        case "orange": .orange
        case "green": .green
        default: .secondary
        }
    }
}

/// Toolbar menu to switch Light / OLED Dark mode quickly (night shifts).
struct AppearanceMenu: View {
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system

    var body: some View {
        Menu {
            Picker("Tampilan", selection: $appearance) {
                ForEach(AppearanceSetting.allCases) { setting in
                    Text(setting.label).tag(setting)
                }
            }
        } label: {
            Image(systemName: "circle.lefthalf.filled")
                .accessibilityLabel("Tampilan terang/gelap")
        }
    }
}
