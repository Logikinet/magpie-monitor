import SwiftUI
import MagpieKit

struct RoutingGroupsView: View {
    let groups: [RoutingGroup]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "路由组")).font(.headline)
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.name ?? group.id ?? "—").font(.subheadline.weight(.semibold))
                    Text("group/\(group.id ?? "—") · \(RoutePresentation.strategy(group.routing))").font(.caption.monospaced())
                    Text(group.members?.elements.joined(separator: " · ") ?? "—").font(.caption.monospaced()).foregroundStyle(DS.Palette.soft)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(DS.Palette.elev, in: RoundedRectangle(cornerRadius: DS.Radius.node))
            }
            if groups.isEmpty { Text(String(localized: "暂无路由组")).foregroundStyle(DS.Palette.dim) }
        }
    }
}
