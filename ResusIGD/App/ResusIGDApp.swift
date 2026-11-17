import SwiftUI
import SwiftData

@main
struct ResusIGDApp: App {
    private let container: ModelContainer
    @State private var library = ClinicalLibrary()
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system

    init() {
        let schema = Schema([
            AdultDrugRecord.self,
            PediatricDrugRecord.self,
            GuidelineRecord.self,
            ResusSessionRecord.self
        ])
        do {
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            // Never block the clinician: fall back to an in-memory store if the on-disk store is unusable.
            do {
                container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            } catch {
                fatalError("Tidak dapat membuat penyimpanan lokal: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(library)
                .preferredColorScheme(appearance.colorScheme)
                .task { library.bootstrap(context: container.mainContext) }
        }
        .modelContainer(container)
    }
}
