import SwiftUI
import MagpieKit

struct RuntimeGatewaySection: View {
    let providers: [Provider]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "模型网关")).font(.headline)
            if providers.isEmpty {
                Text(String(localized: "暂无服务商")).foregroundStyle(DS.Palette.soft)
            }
            ForEach(Array(providers.enumerated()), id: \.offset) { _, provider in
                RuntimeGatewayRow(provider: provider)
            }
        }
        .routingCard()
    }
}

private struct RuntimeGatewayRow: View {
    let provider: Provider
    private var ready: Bool { return provider.key?.set == true || provider.account != nil }
    private var models: [ProviderModel] { return provider.models?.elements ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(provider.name ?? provider.id ?? "—", systemImage: "circle.fill")
                .foregroundStyle(ready ? DS.Palette.green : DS.Palette.dim)
            Text(provider.host ?? "—").font(.caption.monospaced()).textSelection(.enabled)
            Text(ready ? String(localized: "凭据已就绪") : String(localized: "未配置凭据"))
                .font(.caption)
                .foregroundStyle(DS.Palette.soft)
            if !models.isEmpty {
                HorizontalChipRow(minHeight: 32) {
                    ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                        Text(model.id ?? "—")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(DS.Palette.chip, in: Capsule())
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RuntimeEnvironmentSection: View {
    let tools: CollectorRecord?
    private let names = ["node", "python", "git"]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "环境工具")).font(.headline)
            HorizontalChipRow(minHeight: 32) {
                ForEach(names, id: \.self) { name in
                    Text(chip(name))
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(DS.Palette.chip, in: Capsule())
                }
            }
        }
        .routingCard()
    }
    private func chip(_ name: String) -> String {
        return "\(name) \(tools?.string(name) ?? "—")"
    }
}
