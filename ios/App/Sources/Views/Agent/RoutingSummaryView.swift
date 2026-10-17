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
            Text([route.provider ?? "—", route.served ?? route.model ?? "—"].joined(separator: " · ")).font(.headline.monospaced())
            if route.done == false {
                Label("回答中", systemImage: "ellipsis.bubble").foregroundStyle(DS.Palette.green)
            } else if let status = route.status?.value {
                Label("HTTP \(status)", systemImage: status >= 400 ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(status >= 400 ? DS.Palette.red : DS.Palette.green)
            } else { Text("状态：—") }
            Text("耗时 \(RoutePresentation.milliseconds(route.ms?.value)) · 首 token \(RoutePresentation.milliseconds(route.ttft?.value))")
            Text("输入 \(route.tokens?.value.formatted() ?? "—") · 输出 \(route.out?.value.formatted() ?? "—") token")
            Text("输出速度 \(speed)")
        }.font(.caption.monospaced()).accessibilityElement(children: .combine)
    }
}
