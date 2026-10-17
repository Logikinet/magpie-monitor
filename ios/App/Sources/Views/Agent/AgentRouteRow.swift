import SwiftUI
import MagpieKit

struct AgentRouteRow: View {
    let route: Route
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(DS.Palette.agent(route.agent ?? "")).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(route.agent ?? "—").font(.subheadline.weight(.semibold))
                Spacer()
                Text(route.time?.date?.formatted(.dateTime.hour().minute().second()) ?? "—")
                    .font(.caption.monospaced())
            }
            Text("group/\(route.group?.name ?? route.group?.id ?? "—")").font(.caption.monospaced()).foregroundStyle(DS.Palette.soft)
            Text([route.provider ?? "—", route.served ?? route.model ?? "—"].joined(separator: " · "))
                .font(.subheadline.monospaced()).foregroundStyle(RoutePresentation.failed(route) ? DS.Palette.red : DS.Palette.text)
            Text("\(RoutePresentation.milliseconds(route.ms?.value)) · \(route.tokens?.value.formatted() ?? "—") tk · \(route.cost?.value.formatted(.currency(code: "USD").precision(.fractionLength(3...6))) ?? "—")")
                .font(.caption.monospaced()).foregroundStyle(DS.Palette.soft)
            if RoutePresentation.failed(route) { Label("含失败记录", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(DS.Palette.red) }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(16).background(DS.Palette.panel, in: RoundedRectangle(cornerRadius: DS.Radius.node))
        .accessibilityElement(children: .combine)
    }
}
