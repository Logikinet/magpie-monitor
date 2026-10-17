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
            Text(String(format: String(localized: "服务商：%@ · 模型：%@"), locale: Locale.current, String(describing: route.provider ?? "—"), String(describing: route.served ?? route.model ?? "—"))).font(.headline.monospaced())
            if route.done == false {
                let start = route.tries?.elements.first?.start?.date
                Label(String(format: String(localized: "回答中 · 已用 %@"), locale: Locale.current, String(describing: RoutePresentation.elapsed(start))), systemImage: "ellipsis.bubble")
                    .foregroundStyle(DS.Palette.green)
            } else if let status = route.status?.value {
                Label("HTTP \(status)", systemImage: status >= 400 ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(status >= 400 ? DS.Palette.red : DS.Palette.green)
            } else { Text(String(localized: "状态：—")) }
            if route.done != false {
                Text(String(format: String(localized: "耗时：%@ · Token：%@"), locale: Locale.current, String(describing: RoutePresentation.milliseconds(route.ms?.value)), String(describing: route.tokens?.value.formatted() ?? "—")))
            }
            if let ttft = route.ttft?.value ?? route.tries?.elements.first(where: { $0.served == route.served })?.ttft?.value {
                Text(String(format: String(localized: "首字：%@"), locale: Locale.current, String(describing: RoutePresentation.milliseconds(ttft))))
            }
            if route.done != false, let output = route.out?.value { Text(String(format: String(localized: "输出 Token：%@"), locale: Locale.current, String(describing: output.formatted()))) }
            if route.done != false, speed != "—" { Text(String(format: String(localized: "速度：%@"), locale: Locale.current, String(describing: speed))) }
        }.font(.caption.monospaced()).accessibilityElement(children: .combine)
    }
}
