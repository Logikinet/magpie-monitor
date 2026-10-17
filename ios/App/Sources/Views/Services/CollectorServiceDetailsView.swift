import SwiftUI
import MagpieKit

struct CollectorServiceDetailsView: View {
    @Environment(AppState.self) private var appState
    let kind: String
    @State private var data: CollectorRecord?
    @State private var error: String?
    var body: some View {
        List {
            Text(String(localized: "只读信息")).font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(DS.Palette.red) }
            if data == nil && error == nil { ProgressView() }
            if kind == "tasks" {
                let tasks = data?.records("tasks") ?? []
                if data != nil && tasks.isEmpty { Text(String(localized: "暂无数据")) }
                ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.string("name") ?? "—").font(.headline)
                        Text([task.string("kind"), task.string("scope"), task.string("state")].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                        Text(task.string("command") ?? "—").font(.caption.monospaced()).textSelection(.enabled)
                        if let expression = task.string("expr") { Text(expression).font(.caption.monospaced()) }
                    }.padding(.vertical, 8)
                }
            } else if let data {
                Text(data.string("backend_state") ?? "—").font(.headline)
                if let own = data.object("self") { peer(own) }
                ForEach(Array(data.records("peers").enumerated()), id: \.offset) { _, item in peer(item) }
            }
        }.task(id: RefreshContext(profile: appState.currentProfile, isMockMode: appState.isMockMode, isActive: appState.isActive, filters: [kind])) {
            data = nil; error = nil
            guard appState.isActive, let client = appState.makeCollectorClient() else { return }
            do { data = try await (kind == "tasks" ? client.tasks() : client.tailscale()) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func peer(_ item: CollectorRecord) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            Text(item.string("hostname") ?? "—").font(.headline)
            Text(item.string("dns_name") ?? "—").font(.caption.monospaced()).textSelection(.enabled)
            Text(item.flag("online") == true ? String(localized: "在线") : String(localized: "离线")).font(.caption)
        }.padding(.vertical, 8)
    }
}
