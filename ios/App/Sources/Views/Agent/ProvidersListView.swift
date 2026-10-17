import SwiftUI
import MagpieKit

struct ProvidersListView: View {
    let providers: [Provider]
    var body: some View {
        VStack(spacing: 12) {
            if providers.isEmpty { Text(String(localized: "暂无服务商")) }
            ForEach(Array(providers.enumerated()), id: \.offset) { _, provider in
                VStack(alignment: .leading, spacing: 12) {
                    Label(provider.name ?? provider.id ?? "—", systemImage: symbol(provider)).font(.headline)
                    Text(subline(provider)).font(.caption).foregroundStyle(DS.Palette.soft)
                    HStack(spacing: 8) {
                        ForEach(Array((provider.agents?.elements ?? []).filter { $0.current == true }.enumerated()), id: \.offset) { _, agent in
                            Text(String((agent.name ?? agent.id ?? "?").prefix(1)).uppercased())
                                .font(.caption.bold()).padding(8).background(DS.Palette.agent(agent.id ?? ""), in: Circle())
                                .accessibilityLabel(agent.name ?? agent.id ?? "Agent")
                        }
                        Spacer()
                        Text(status(provider)).font(provider.account == nil && provider.key?.set == true ? .caption.monospaced() : .caption)
                            .padding(8).background(DS.Palette.hover, in: Capsule())
                    }
                    if provider.off == true { Text(String(localized: "已停用")).font(.caption) }
                }.routingCard().opacity(provider.off == true ? 0.5 : 1)
            }
        }
    }
    private func symbol(_ provider: Provider) -> String {
        switch provider.icon {
        case "key": "key.fill"
        case "cloud", "openrouter": "cloud.fill"
        case "terminal", "codex": "terminal.fill"
        default: "server.rack"
        }
    }
    private func status(_ provider: Provider) -> String {
        if let account = provider.account { return account.plan ?? String(localized: "已登录") }
        if provider.key?.set == true { return provider.key?.masked ?? "—" }
        return String(localized: "免费")
    }
    private func subline(_ provider: Provider) -> String {
        let source = provider.account?.user.map { String(localized: "登录账号") + " " + $0 } ?? provider.host ?? "—"
        return source + " · " + (provider.activeModelsCount?.value ?? provider.models?.elements.count ?? 0).formatted() + " " + String(localized: "模型")
    }
}
