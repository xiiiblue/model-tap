import SwiftUI
import SwiftData

@main
struct ModelTapApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([APIProfile.self, ProfileFolder.self, ModelTestRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法创建本地数据存储：\(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(modelContext: sharedModelContainer.mainContext)
        }
        .windowToolbarStyle(.unifiedCompact)
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建配置") {
                    NotificationCenter.default.post(name: .modelTapNewProfile, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let modelTapNewProfile = Notification.Name("ModelTap.newProfile")
}
