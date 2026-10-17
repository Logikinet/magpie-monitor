import SwiftUI
import MagpieKit

struct RoutingStageView: View {
    let routes: [Route]
    let route: Route
    let now: Date
    @Binding var seatFilter: String?
    var masked = true
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var compact: Bool { sizeClass == .compact || typeSize.isAccessibilitySize }
    private var agents: [String] {
        var names: [String] = []
        for route in routes.prefix(10) {
            if let name = route.agent, !names.contains(name) { names.append(name) }
        }
        return Array(names.prefix(3))
    }
    private var seats: [Seat] {
        var seen: Set<String> = []
        return ((route.order?.elements ?? []) + (route.left?.elements ?? [])).filter {
            seen.insert(RoutingModel.seatKey(id: $0.id ?? "", model: $0.model)).inserted
        }
    }
    private var hub: some View {
        VStack(spacing: 8) {
            Text("M").font(.title.bold()).foregroundStyle(DS.Palette.accent)
            Text("magpie").font(.headline)
            Text(RoutePresentation.strategy(route.group?.routing)).font(.caption)
                .padding(8).background(DS.Palette.hover, in: Capsule())
        }
        .frame(maxWidth: .infinity).padding(16)
        .background(DS.Palette.elev, in: RoundedRectangle(cornerRadius: DS.Radius.node))
        .anchorPreference(key: RoutingAnchors.self, value: .bounds) { ["hub": $0] }
    }
    private var agentNodes: some View {
        VStack(spacing: 16) {
            ForEach(agents, id: \.self) { agent in
                Label(agent, systemImage: "terminal").font(.subheadline)
                    .foregroundStyle(DS.Palette.agent(agent))
                    .frame(maxWidth: .infinity, minHeight: 44).padding(8)
                    .background(DS.Palette.elev, in: RoundedRectangle(cornerRadius: DS.Radius.node))
                    .anchorPreference(key: RoutingAnchors.self, value: .bounds) { ["agent:" + agent: $0] }
            }
        }
    }
    var seatNodes: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(RoutingModel.groupedSeats(seats), id: \.key) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text([group.provider, group.model].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption.monospaced()).foregroundStyle(DS.Palette.soft)
                    if group.needsSubheader {
                        Text(String(format: String(localized: "%@ 个账号 · %@ 个可用"), locale: Locale.current, String(describing: group.seats.count), String(describing: group.seats.filter { $0.rest == nil }.count)))
                            .font(.caption).foregroundStyle(DS.Palette.dim)
                    }
                    ForEach(Array(group.seats.enumerated()), id: \.offset) { _, seat in
                        seatNode(seat)
                    }
                }
            }
            if seats.isEmpty { Text(String(localized: "暂无候选节点")).foregroundStyle(DS.Palette.dim) }
        }
    }
    private func seatNode(_ seat: Seat) -> some View {
        let key = RoutingModel.seatKey(id: seat.id ?? "", model: seat.model)
        let state = RoutingModel.state(of: seat, in: route)
        let on = state == .trying || state == .answered
        return Button {
            seatFilter = seatFilter == key ? nil : key
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(masked ? (seat.name ?? String(localized: "账号已隐藏")) : (seat.who ?? seat.name ?? "—"), systemImage: on ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text([seat.plan, seat.model, seat.fallback == true ? String(localized: "备用") : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.monospaced())
                Text(RoutePresentation.status(seat, route: route, now: now)).font(.caption)
                if let used = seat.used?.value, used.isFinite, seat.known == true {
                    ProgressView(value: min(100, max(0, 100 - used)), total: 100)
                        .tint(on ? DS.Palette.green : DS.Palette.quotaGreen)
                }
            }
            .foregroundStyle(on ? DS.Palette.green : DS.Palette.text)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
            .background(on ? DS.Palette.green.opacity(0.08) : DS.Palette.elev, in: RoundedRectangle(cornerRadius: DS.Radius.node))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.node).stroke(seatFilter == key ? DS.Palette.accent : (on ? DS.Palette.green.opacity(0.4) : DS.Palette.border)))
            .opacity(state == .rest ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "筛选此账号的请求，再次点击取消"))
        .accessibilityAddTraits(seatFilter == key ? .isSelected : [])
        .anchorPreference(key: RoutingAnchors.self, value: .bounds) { ["seat:" + key: $0] }
    }
    var body: some View {
        Group {
            if compact {
                HStack(spacing: 8) {
                    compactNode(route.agent ?? "—", detail: route.model ?? "—", anchor: "agent:" + (route.agent ?? "—"))
                    hub
                    compactNode(route.provider ?? "—", detail: route.served ?? route.model ?? "—", anchor: "served")
                }
            } else {
                HStack(alignment: .center, spacing: 40) {
                    agentNodes.frame(width: 120)
                    hub.frame(width: 120)
                    seatNodes.frame(maxWidth: .infinity)
                }
            }
        }
        .overlayPreferenceValue(RoutingAnchors.self) { anchors in
            GeometryReader { geometry in
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                    let phase = reduceMotion ? 0 : -8 * timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.7) / 0.7
                    if let hubAnchor = anchors["hub"] {
                        let hubRect = geometry[hubAnchor]
                        ForEach(agents, id: \.self) { agent in
                            if let anchor = anchors["agent:" + agent] {
                                wire(from: geometry[anchor], to: hubRect, live: route.agent == agent, phase: phase)
                            }
                        }
                        if compact, let served = anchors["served"] {
                            wire(from: hubRect, to: geometry[served], live: true, phase: phase)
                        }
                        if !compact {
                            ForEach(Array(seats.enumerated()), id: \.offset) { _, seat in
                                if let anchor = anchors["seat:" + RoutingModel.seatKey(id: seat.id ?? "", model: seat.model)] {
                                    let state = RoutingModel.state(of: seat, in: route)
                                    wire(from: hubRect, to: geometry[anchor], live: state == .trying || state == .answered, phase: phase)
                                }
                            }
                        }
                    }
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
    private func compactNode(_ title: String, detail: String, anchor: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(DS.Palette.soft)
        }.frame(maxWidth: .infinity, minHeight: 80).padding(8)
            .background(DS.Palette.elev, in: RoundedRectangle(cornerRadius: DS.Radius.node))
            .anchorPreference(key: RoutingAnchors.self, value: .bounds) { [anchor: $0] }
    }
    private func wire(from source: CGRect, to target: CGRect, live: Bool, phase: Double) -> some View {
        Path { path in
            if target.minX > source.maxX {
                let middle = (source.maxX + target.minX) / 2
                path.move(to: CGPoint(x: source.maxX, y: source.midY))
                path.addCurve(to: CGPoint(x: target.minX, y: target.midY), control1: CGPoint(x: middle, y: source.midY), control2: CGPoint(x: middle, y: target.midY))
            } else {
                path.move(to: CGPoint(x: source.midX, y: source.maxY))
                path.addLine(to: CGPoint(x: target.midX, y: target.minY))
            }
        }
        .stroke(live ? DS.Palette.agent(route.agent ?? "") : DS.Palette.border, style: StrokeStyle(lineWidth: 1.5, dash: live ? [3, 5] : [], dashPhase: CGFloat(phase)))
    }
}
