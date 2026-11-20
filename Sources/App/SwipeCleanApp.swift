import SwiftUI
import SwiftData

@main
struct SwipeCleanApp: App {
    @State private var settings = AppSettings.shared
    @State private var photoService = PhotoLibraryService()
    let container: ModelContainer?
    let decisionStore: DecisionStore?

    init() {
        let schema = Schema([
            MediaDecisionRecord.self,
            CleaningStatsRecord.self
        ])

        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let loaded = try ModelContainer(for: schema, configurations: [config])
            self.container = loaded
            self.decisionStore = DecisionStore(modelContext: loaded.mainContext)
        } catch {
            print("⚠️ SwipeCleanApp: Не удалось создать постоянный ModelContainer (\(error)). Переключение на in-memory.")
            do {
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                let loaded = try ModelContainer(for: schema, configurations: [memoryConfig])
                self.container = loaded
                self.decisionStore = DecisionStore(modelContext: loaded.mainContext)
            } catch {
                print("⚠️ SwipeCleanApp: Критическая ошибка создания in-memory ModelContainer: \(error)")
                self.container = nil
                self.decisionStore = nil
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container, let decisionStore {
                    RootView()
                        .environment(settings)
                        .environment(photoService)
                        .environment(decisionStore)
                        .modelContainer(container)
                } else {
                    ContentUnavailableView(
                        "Ошибка инициализации",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("Не удалось инициализировать локальное хранилище данных.")
                    )
                }
            }
            .preferredColorScheme(settings.theme.colorScheme)
        }
    }
}
