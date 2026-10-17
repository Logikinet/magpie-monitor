import SwiftUI
import MagpieKit

struct AgentRouteRow: View {
    let route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            Text(route.agent ?? "未知 Agent").font(.headline)
            Text(route.model ?? "未知模型").font(.subheadline.monospaced())
            Text(route.provider ?? "未知提供方").font(.subheadline).foregroundStyle(.secondary)
            if let rule = route.rule?.name { Text("规则：\(rule)").font(.subheadline) }
            if let group = route.group?.name { Text("分组：\(group)").font(.subheadline) }
            if let date = route.time?.date {
                Text(date, format: .dateTime.hour().minute().second()).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text(route.time?.rawString ?? "时间未知").font(.footnote).foregroundStyle(.secondary)
            }
            if route.subagent != nil { Label("子 Agent", systemImage: "arrow.triangle.branch").font(.footnote) }
            if let pinned = route.pinned, !pinned.isEmpty { Label("已固定", systemImage: "pin.fill").font(.footnote) }
            if route.error?.isEmpty == false || (route.status?.value ?? 0) >= 400 {
                StatusBadge(kind: .error, text: "路由错误")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(DS.Spacing.medium)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: DS.Radius.card))
        .accessibilityElement(children: .combine)
    }
}
