import SwiftUI

@main
@MainActor
struct MagpieApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                tab(OverviewView(), title: "概览", symbol: "gauge")
                tab(ActivityView(), title: "动态", symbol: "list.bullet.rectangle")
                tab(TmuxView(), title: "Tmux", symbol: "terminal")
                tab(AgentView(), title: "Agent", symbol: "point.3.connected.trianglepath.dotted")
                tab(ServicesView(), title: "服务", symbol: "server.rack")
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
