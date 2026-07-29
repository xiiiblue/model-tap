import SwiftUI
import SwiftData

@main
struct ModelTapApp: App {
    private let storeState: StoreState

    init() {
        do {
            storeState = .ready(
                try PersistentStoreBootstrap.makeContainer()
            )
        } catch {
            storeState = .failed(error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch storeState {
            case .ready(let container):
                ContentView(modelContext: container.mainContext)
                    .modelContainer(container)
            case .failed(let message):
                PersistentStoreErrorView(message: message)
            }
        }
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

private enum StoreState {
    case ready(ModelContainer)
    case failed(String)
}

private struct PersistentStoreErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("无法打开本地数据", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("ModelTap无法访问本地配置数据库。请确认磁盘空间和“应用支持”目录权限后重新打开应用。\n\n\(message)")
        }
        .frame(minWidth: 680, minHeight: 480)
        .padding(40)
    }
}

extension Notification.Name {
    static let modelTapNewProfile = Notification.Name("ModelTap.newProfile")
}
