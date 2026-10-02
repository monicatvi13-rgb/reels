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
    @State private var navigator = AppNavigator.shared

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
        // Siri или кнопка «Действие» попросили поговорить — открываем разговор.
        .onChange(of: navigator.talkRequest) { _, request in
            if request != nil { tab = .ask }
        }
        .onAppear {
            if navigator.talkRequest != nil { tab = .ask }
        }
        // Ссылка из виджета: offload://talk
        .onOpenURL { url in
            if url.scheme == "offload" && url.host == "talk" {
                navigator.requestTalk()
            }
        }
    }
}

extension Notification.Name {
    /// Поменялись настройки уведомлений или Календаря — пора пересобрать.
    static let offloadSettingsChanged = Notification.Name("offloadSettingsChanged")
}

#Preview {
    RootView()
        .modelContainer(for: [BrainDump.self, OffloadItem.self, ChatEntry.self], inMemory: true)
}
