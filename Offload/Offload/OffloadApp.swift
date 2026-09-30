import SwiftUI
import SwiftData

@main
struct OffloadApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
        }
        // Всё надиктованное и разложенное хранится на устройстве между запусками.
        .modelContainer(for: [BrainDump.self, OffloadItem.self])
    }
}
