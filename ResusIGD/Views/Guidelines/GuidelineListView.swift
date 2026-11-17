import SwiftUI
import ClinicalCore

struct GuidelineListView: View {
    @Environment(ClinicalLibrary.self) private var library
    @State private var model = GuidelineListViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    categoryFilter
                    if model.results.isEmpty {
                        ContentUnavailableView.search(text: model.query)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(model.results) { guideline in
                            NavigationLink(value: guideline.id) {
                                GuidelineCard(guideline: guideline)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 80)
            }
            .background(Theme.background)
            .navigationTitle("Guideline IGD")
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cari: stroke, stemi, kejang, parkland…")
            .textInputAutocapitalization(.never)
            .navigationDestination(for: String.self) { id in
                if let guideline = model.guidelines.first(where: { $0.id == id }) {
                    GuidelineDetailView(guideline: guideline)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { AppearanceMenu() } }
        }
        .onAppear { model.load(guidelines: library.guidelines) }
        .onChange(of: library.guidelines) { _, guidelines in model.load(guidelines: guidelines) }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, label: "Semua", color: .accentColor)
                ForEach(model.categoriesInUse) { chip($0, label: $0.label, color: Theme.color(for: $0)) }
            }
        }
    }

    private func chip(_ category: GuidelineCategory?, label: String, color: Color) -> some View {
        let selected = model.category == category
        return Button { model.category = category } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(selected ? color : Theme.card, in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct GuidelineCard: View {
    let guideline: Guideline

    var body: some View {
        let color = Theme.color(for: guideline.category)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: Theme.icon(for: guideline.category))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(color, in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                if !guideline.calculators.isEmpty {
                    Image(systemName: "function").font(.caption.weight(.bold)).foregroundStyle(color)
                        .accessibilityLabel("Berisi kalkulator")
                }
            }
            Text(guideline.title)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(guideline.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.cornerRadius, topTrailingRadius: Theme.cornerRadius)
                .fill(color)
                .frame(height: 5)
        }
    }
}
