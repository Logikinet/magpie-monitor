import SwiftUI
import MagpieKit

struct AgentRouteDetailView: View {
    let route: Route
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("路由") {
                    AgentRouteRow(route: route)
                    if let id = route.id?.value { Text("路由 ID：\(id.formatted())") }
                    if let session = route.session { Text("会话：\(session)") }
                    if let parent = route.parentSession { Text("父会话：\(parent)") }
                    if let reason = route.rule?.reason { Text("规则依据：\(reason)") }
                    if let name = route.subagent?.name { Text("子 Agent：\(name)") }
                    if let pinned = route.pinned, !pinned.isEmpty { Text("固定：\(pinned)") }
                }
                Section {
                    ForEach(Array((route.order?.elements ?? []).enumerated()), id: \.offset) { index, candidate in
                        VStack(alignment: .leading, spacing: DS.Spacing.small) {
                            Text("\(index + 1). \(candidate.name ?? candidate.provider ?? "候选")").font(.headline)
                            Text([candidate.provider, candidate.model, candidate.kind].compactMap { $0 }.joined(separator: " · ")).font(.subheadline.monospaced())
                            if let routing = candidate.routing { Text("调度：\(routing)") }
                            if let used = candidate.used?.value { Text("用量占比：\((used / 100).formatted(.percent))") }
                            if let amount = candidate.amount?.value { Text("用量：\(amount.formatted()) \(candidate.unit ?? "")") }
                            if let limit = candidate.limit?.value { Text("额度：\(limit.formatted()) \(candidate.unit ?? "")") }
                            if let pace = candidate.pace?.value { Text("每小时剩余额度：\(pace.formatted())") }
                            if let tokens = candidate.tokens?.value { Text("近期 Token：\(tokens.formatted())") }
                            if let rank = candidate.rank?.value { Text("提供方排序：\(rank.formatted())") }
                            if candidate.turn == true { Text("当前轮次") }
                            if candidate.fallback == true { Text("备用候选") }
                        }
                        .font(.subheadline).monospacedDigit()
                    }
                    if route.order?.elements.isEmpty != false { Text("暂无候选数据") }
                } header: { Text("候选顺序与调度依据") } footer: { Text("按服务端返回的尝试顺序排列；仅显示服务器提供的指标。") }
            }
            .textSelection(.enabled)
            .navigationTitle("路由详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
