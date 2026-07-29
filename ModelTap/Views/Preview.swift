import SwiftUI
import SwiftData

#Preview("配置与模型") {
    ContentView()
        .modelContainer(for: [APIProfile.self, ProfileFolder.self, ModelTestRecord.self], inMemory: true)
}
