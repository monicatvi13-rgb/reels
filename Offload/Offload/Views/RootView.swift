import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case dump
    case ask
    case lists
}

/// Три вкладки: «Выгрузить», «Спросить» и «Списки».
struct RootView: View {
    @Query(sort: \OffloadItem.createdAt) private var items: [OffloadItem]
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .dump

    var body: some View {
        TabView(selection: $tab) {
            DumpView(tab: $tab)
                .tabItem { Label("Выгрузить", systemImage: "waveform") }
                .tag(AppTab.dump)

            AssistantView()
                .tabItem { Label("Спросить", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(AppTab.ask)

            ListsView()
                .tabItem { Label("Списки", systemImage: "checklist") }
                .tag(AppTab.lists)
        }
        // Любое изменение в списках — обновляем уведомления и Календарь.
        // Небольшая пауза, чтобы не дёргаться на каждую букву при редактировании.
        .task(id: AppSync.signature(of: items)) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await AppSync.refresh(items)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await AppSync.refresh(items) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .offloadSettingsChanged)) { _ in
            Task { await AppSync.refresh(items) }
        }
    }
}

extension Notification.Name {
    /// Поменялись настройки уведомлений или Календаря — пора пересобрать.
    static let offloadSettingsChanged = Notification.Name("offloadSettingsChanged")
}

#Preview {
    RootView()
        .modelContainer(for: [BrainDump.self, OffloadItem.self], inMemory: true)
}
