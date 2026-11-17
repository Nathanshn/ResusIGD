import SwiftUI

enum AppTab: Hashable {
    case titration
    case pediatric
    case guidelines
    case codeTimer
}

struct RootTabView: View {
    @Environment(ClinicalLibrary.self) private var library
    @State private var selection: AppTab = .titration

    var body: some View {
        TabView(selection: $selection) {
            TitrationView()
                .codeBlueOverlay(selection: $selection)
                .tabItem { Label("Titrasi", systemImage: "syringe.fill") }
                .tag(AppTab.titration)

            PediatricView()
                .codeBlueOverlay(selection: $selection)
                .tabItem { Label("Pediatri", systemImage: "figure.child") }
                .tag(AppTab.pediatric)

            GuidelineListView()
                .codeBlueOverlay(selection: $selection)
                .tabItem { Label("Guideline", systemImage: "book.closed.fill") }
                .tag(AppTab.guidelines)

            CodeTimerView()
                .tabItem { Label("Code Timer", systemImage: "timer") }
                .tag(AppTab.codeTimer)
        }
        .overlay {
            if library.adultDrugs.isEmpty && library.loadError == nil {
                ProgressView("Memuat database lokal…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

private struct CodeBlueOverlay: ViewModifier {
    @Binding var selection: AppTab

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            CodeBlueButton { selection = .codeTimer }
        }
    }
}

extension View {
    func codeBlueOverlay(selection: Binding<AppTab>) -> some View {
        modifier(CodeBlueOverlay(selection: selection))
    }
}
