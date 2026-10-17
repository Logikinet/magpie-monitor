import SwiftUI
import MagpieKit

struct AgentRouteDetailView: View {
    let route: Route
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AgentRouteRow(route: route)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("路由经过").font(.headline)
                        Text("分组：\(route.group?.name ?? route.group?.id ?? "—")")
                        Text("调度：\(RoutePresentation.strategy(route.group?.routing))")
                        if let reason = route.rule?.reason { Text("规则：\(reason)") }
                        if let error = route.error, !error.isEmpty { Text(error).foregroundStyle(DS.Palette.red) }
                        Text("尝试记录").font(.headline)
                        ForEach(Array((route.tries?.elements ?? []).enumerated()), id: \.offset) { index, attempt in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(index + 1). \(attempt.id ?? "—") · \(attempt.served ?? attempt.model ?? "—")").font(.subheadline.monospaced())
                                Text(attempt.start?.date?.formatted(.dateTime.hour().minute().second()) ?? "—").font(.caption.monospaced())
                                Text("\(attempt.done == true ? "已结束" : (attempt.done == false ? "进行中" : "—")) · HTTP \(attempt.status?.value.formatted() ?? "—") · \(RoutePresentation.milliseconds(attempt.ms?.value))")
                                    .font(.caption.monospaced()).foregroundStyle((attempt.status?.value ?? 0) >= 400 ? DS.Palette.red : DS.Palette.soft)
                                Text("首 token \(RoutePresentation.milliseconds(attempt.ttft?.value)) · 首文字 \(RoutePresentation.milliseconds(attempt.firstText?.value))").font(.caption.monospaced())
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(DS.Palette.elev, in: RoundedRectangle(cornerRadius: DS.Radius.node))
                        }
                        if route.tries?.elements.isEmpty != false { Text("暂无尝试记录").foregroundStyle(DS.Palette.dim) }
                    }
                    LatencyBarView(route: route)
                    ContextWaffleView(route: route)
                    Text("会话：\(route.session ?? "—")").font(.caption.monospaced()).textSelection(.enabled)
                    if let parent = route.parentSession { Text("父会话：\(parent)").font(.caption.monospaced()).textSelection(.enabled) }
                }.padding(16)
            }
            .background(DS.Palette.bg).navigationTitle("请求详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
