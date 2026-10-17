import SwiftUI
import MagpieKit

struct LatencyBarView: View {
    let route: Route
    private var segments: [(String, Int?, Color)] {
        let first = route.firstText?.value ?? route.ttft?.value
        let stream = (route.ms?.value).flatMap { total in first.flatMap { total >= $0 && $0 >= 0 ? total - $0 : nil } }
        return [("首 token", route.ttft?.value, DS.Palette.blue),
                ("首文字", route.firstText?.value, DS.Palette.orange),
                ("流式输出", stream, DS.Palette.green)]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("延迟").font(.headline)
            Text("总耗时：\(RoutePresentation.milliseconds(route.ms?.value))").font(.subheadline.monospaced())
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
