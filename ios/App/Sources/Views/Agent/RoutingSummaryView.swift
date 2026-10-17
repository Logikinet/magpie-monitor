import SwiftUI
import MagpieKit

struct RoutingSummaryView: View {
    let route: Route
    private var speed: String {
        guard let out = route.out?.value, out >= 0,
              let total = route.ms?.value,
              let first = route.firstText?.value ?? route.ttft?.value,
              first >= 0, total > first else { return "—" }
        return (Double(out) * 1000 / Double(total - first)).formatted(.number.precision(.fractionLength(1))) + " tok/s"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("服务商：\(route.provider ?? "—") · 模型：\(route.served ?? route.model ?? "—")").font(.headline.monospaced())
            if route.done == false {
                let start = route.tries?.elements.first?.start?.date
                Label("回答中 · 已用 \(RoutePresentation.elapsed(start))", systemImage: "ellipsis.bubble")
                    .foregroundStyle(DS.Palette.green)
            } else if let status = route.status?.value {
                Label("HTTP \(status)", systemImage: status >= 400 ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(status >= 400 ? DS.Palette.red : DS.Palette.green)
            } else { Text("状态：—") }
            if route.done != false {
                Text("耗时：\(RoutePresentation.milliseconds(route.ms?.value)) · Token：\(route.tokens?.value.formatted() ?? "—")")
            }
            if let ttft = route.ttft?.value ?? route.tries?.elements.first(where: { $0.served == route.served })?.ttft?.value {
                Text("首字：\(RoutePresentation.milliseconds(ttft))")
            }
            if route.done != false, let output = route.out?.value { Text("输出 Token：\(output.formatted())") }
            if route.done != false, speed != "—" { Text("速度：\(speed)") }
        }.font(.caption.monospaced()).accessibilityElement(children: .combine)
    }
}
