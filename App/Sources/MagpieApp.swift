import SwiftUI

@main
struct MagpieApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                PlaceholderTab(title: "概览", symbol: "gauge")
                    .tabItem { Label("概览", systemImage: "gauge") }
                PlaceholderTab(title: "动态", symbol: "list.bullet.rectangle")
                    .tabItem { Label("动态", systemImage: "list.bullet.rectangle") }
                PlaceholderTab(title: "Tmux", symbol: "terminal")
                    .tabItem { Label("Tmux", systemImage: "terminal") }
                PlaceholderTab(title: "Agent", symbol: "point.3.connected.trianglepath.dotted")
                    .tabItem { Label("Agent", systemImage: "point.3.connected.trianglepath.dotted") }
                PlaceholderTab(title: "服务", symbol: "server.rack")
                    .tabItem { Label("服务", systemImage: "server.rack") }
            }
        }
    }
}

private struct PlaceholderTab: View {
    let title: String
    let symbol: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: symbol)
                .navigationTitle(title)
        }
    }
}
