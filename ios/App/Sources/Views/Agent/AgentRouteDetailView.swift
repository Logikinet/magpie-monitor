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
                        Text(String(localized: "路由经过")).font(.headline)
                        Text(String(format: String(localized: "分组：%@"), locale: Locale.current, String(describing: route.group?.name ?? route.group?.id ?? "—")))
                        Text(String(format: String(localized: "调度：%@"), locale: Locale.current, String(describing: RoutePresentation.strategy(route.group?.routing))))
                        if let reason = route.rule?.reason { Text(String(format: String(localized: "规则：%@"), locale: Locale.current, String(describing: reason))) }
                        if let error = route.error, !error.isEmpty { Text(error).foregroundStyle(DS.Palette.red) }
                        Text(String(localized: "尝试记录")).font(.headline)
                        ForEach(Array((route.tries?.elements ?? []).enumerated()), id: \.offset) { index, attempt in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(index + 1). \(attempt.id ?? "—") · \(attempt.served ?? attempt.model ?? "—")").font(.subheadline.monospaced())
                                Text(attempt.start?.date?.formatted(.dateTime.hour().minute().second()) ?? "—").font(.caption.monospaced())
                                Text("\(attempt.done == true ? String(localized: "已结束") : (attempt.done == false ? String(localized: "进行中") : "—")) · HTTP \(attempt.status?.value.formatted() ?? "—") · \(RoutePresentation.milliseconds(attempt.ms?.value))")
                                    .font(.caption.monospaced()).foregroundStyle((attempt.status?.value ?? 0) >= 400 ? DS.Palette.red : DS.Palette.soft)
                                Text(String(format: String(localized: "首 token %@ · 首文字 %@"), locale: Locale.current, String(describing: RoutePresentation.milliseconds(attempt.ttft?.value)), String(describing: RoutePresentation.milliseconds(attempt.firstText?.value)))).font(.caption.monospaced())
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(DS.Palette.elev, in: RoundedRectangle(cornerRadius: DS.Radius.node))
                        }
                        if route.tries?.elements.isEmpty != false { Text(String(localized: "暂无尝试记录")).foregroundStyle(DS.Palette.dim) }
                    }
                    LatencyBarView(route: route)
                    ContextWaffleView(route: route)
                    Text(String(format: String(localized: "会话：%@"), locale: Locale.current, String(describing: route.session ?? "—"))).font(.caption.monospaced()).textSelection(.enabled)
                    if let parent = route.parentSession { Text(String(format: String(localized: "父会话：%@"), locale: Locale.current, String(describing: parent))).font(.caption.monospaced()).textSelection(.enabled) }
                }.padding(16)
            }
            .background(DS.Palette.bg).navigationTitle(String(localized: "请求详情")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "完成")) { dismiss() } } }
        }
    }
}
