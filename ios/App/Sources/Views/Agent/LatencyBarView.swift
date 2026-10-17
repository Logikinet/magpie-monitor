import SwiftUI
import MagpieKit

struct LatencyBarView: View {
    let route: Route
    private var segments: [(String, Int?, Color)] {
        let ttft = route.ttft?.value ?? route.tries?.elements.first(where: { $0.served == route.served })?.ttft?.value
        let first = route.firstText?.value ?? ttft
        let stream = (route.ms?.value).flatMap { total in first.flatMap { total >= $0 && $0 >= 0 ? total - $0 : nil } }
        return [(String(localized: "首 token"), ttft, DS.Palette.blue),
                (String(localized: "首文字"), route.firstText?.value, DS.Palette.orange),
                (String(localized: "流式输出"), stream, DS.Palette.green)]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "延迟")).font(.headline)
            Text(String(format: String(localized: "总耗时：%@"), locale: Locale.current, String(describing: RoutePresentation.milliseconds(route.ms?.value)))).font(.subheadline.monospaced())
            // TTFT and firstText overlap: show independent measurements rather than invented phases.
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(segment.0)：\(RoutePresentation.milliseconds(segment.1))").font(.caption.monospaced())
                    if let value = segment.1, let total = route.ms?.value, total > 0 {
                        ProgressView(value: Double(max(0, min(value, total))), total: Double(total)).tint(segment.2)
                    }
                }
            }
            Text("DNS / TCP / TLS：—").font(.caption).foregroundStyle(DS.Palette.dim)
        }
    }
}
