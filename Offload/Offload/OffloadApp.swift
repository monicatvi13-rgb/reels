import SwiftUI
import SwiftData
import UserNotifications

@main
struct OffloadApp: App {
    init() {
        // Уведомления показываются, даже когда приложение открыто.
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
        }
        // Всё надиктованное и разложенное хранится на устройстве между запусками.
        .modelContainer(for: [BrainDump.self, OffloadItem.self])
    }
}
