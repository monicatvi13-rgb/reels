import SwiftUI

enum AppTab: Hashable {
    case dump
    case lists
}

/// Две вкладки: «Выгрузить» (слив мыслей) и «Списки».
struct RootView: View {
    @State private var tab: AppTab = .dump

    var body: some View {
        TabView(selection: $tab) {
            DumpView(tab: $tab)
                .tabItem { Label("Выгрузить", systemImage: "waveform") }
                .tag(AppTab.dump)

            ListsView()
                .tabItem { Label("Списки", systemImage: "checklist") }
                .tag(AppTab.lists)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [BrainDump.self, OffloadItem.self], inMemory: true)
}
