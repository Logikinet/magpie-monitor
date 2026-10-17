import SwiftUI

@main
@MainActor
struct MagpieApp: App {
    @State private var appState = AppState()
    @State private var selectedTab = {
        let tab = UserDefaults.standard.integer(forKey: "initialTab")
        return (0...4).contains(tab) ? tab : 0
    }()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                tab(OverviewView(), title: "概览", symbol: "gauge").tag(0)
                tab(ActivityView(), title: "动态", symbol: "list.bullet.rectangle").tag(1)
                tab(TmuxView(), title: "Tmux", symbol: "terminal").tag(2)
                tab(AgentView(), title: "Agent", symbol: "point.3.connected.trianglepath.dotted").tag(3)
                tab(ServicesView(), title: "服务", symbol: "server.rack").tag(4)
            }
            .environment(appState)
            .onChange(of: scenePhase, initial: true) { _, phase in appState.isActive = phase == .active }
        }
    }
    private func tab<V: View>(_ view: V, title: String, symbol: String) -> some View {
        NavigationStack {
            view
                .id("\(appState.currentProfile?.id.uuidString ?? "none")-\(appState.isMockMode)")
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
                .profileToolbar()
        }
        .tabItem { Label(title, systemImage: symbol) }
    }
}
