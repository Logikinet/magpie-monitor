import SwiftUI
import MagpieKit

@MainActor
struct AgentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    private var compact: Bool { sizeClass == .compact || typeSize.isAccessibilitySize }
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = AgentStore()
    @State private var visible = false
    @State private var tab = {
        let value = UserDefaults.standard.string(forKey: "agentTab") ?? "routing"
        return ["routing", "usage", "providers", "runtimes"].contains(value) ? value : "routing"
    }()
    @State private var showDetail = false
    @State private var masked = true
    private let columns = [GridItem(.adaptive(minimum: 230), alignment: .top)]
    private var filteredRoutes: [Route] {
        guard let key = store.seatFilter else { return store.routes }
        let pieces = key.split(separator: "\0", omittingEmptySubsequences: false)
        let id = pieces.first.map(String.init) ?? ""
        let model = pieces.count > 1 ? String(pieces[1]) : ""
        return store.routes.filter { route in
            let tries = route.tries?.elements ?? []
            let exact = tries.contains { RoutingModel.seatKey(id: $0.id ?? "", model: $0.model) == key }
            return exact || (!tries.contains { $0.id == id && $0.model != nil } && tries.contains { $0.id == id }) || (model.isEmpty && tries.contains { $0.id == id })
        }
    }
    var body: some View {
        @Bindable var store = store
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    Picker(String(localized: "Agent 页面"), selection: $tab) {
                        Text(String(localized: "路由")).tag("routing")
                        Text(String(localized: "用量")).tag("usage")
                        Text(String(localized: "服务商")).tag("providers")
                        Text(String(localized: "运行时")).tag("runtimes")
                    }.pickerStyle(.segmented)
                    if store.configurationMissing && tab != "runtimes" {
                        EmptyStateView(title: String(localized: "配置实时路由"), description: String(localized: "请在设置中填写 Web 地址和 runtime key。"), systemImage: "point.3.connected.trianglepath.dotted")
                    } else {
                        StatusBadge(kind: store.authFailed ? .error : (store.status == .live ? .ok : .neutral), text: store.statusText)
                        if store.authFailed { Text(String(localized: "认证失败，请在设置中更新 runtime key。")).foregroundStyle(DS.Palette.red) }
                        switch tab {
                        case "usage": UsageView(store: store)
                        case "providers":
                            if let error = store.routingError { Text(error).foregroundStyle(DS.Palette.red) }
                            ProvidersListView(providers: store.providers)
                        case "runtimes": RuntimesView(providers: store.providers)
                        default: routing
                        }
                    }
                }
                .padding(16).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
            }
            .onChange(of: store.seatFilter) { _, _ in
                if reduceMotion { scroll.scrollTo("requests", anchor: .top) }
                else { withAnimation { scroll.scrollTo("requests", anchor: .top) } }
            }
        }
        .background(DS.Palette.bg).foregroundStyle(DS.Palette.text)
        .onAppear { visible = true; restart() }
        .onDisappear { visible = false; store.stop(); showDetail = false }
        .onChange(of: scenePhase) { _, _ in restart() }
        .onChange(of: appState.isActive) { _, _ in restart() }
        .onChange(of: appState.currentProfile) { _, _ in showDetail = false; restart() }
        .onChange(of: appState.isMockMode) { _, _ in showDetail = false; restart() }
        .sheet(isPresented: $showDetail) {
            if let route = store.currentRoute { AgentRouteDetailView(route: route) }
        }
    }
    private func restart() {
        if visible && scenePhase == .active && appState.isActive { store.start(appState: appState) } else { store.stop() }
    }
    private var routing: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 24) {
            if let error = store.routingError { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline) }
            if let route = store.currentRoute {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(format: String(localized: "%@ · 路由组"), locale: Locale.current, String(describing: route.group?.name ?? route.group?.id ?? "—"))).font(.headline)
                    Text(String(format: String(localized: "%@ 个候选节点"), locale: Locale.current, String(describing: (route.order?.elements ?? []).filter { $0.fallback != true }.count))).font(.caption).foregroundStyle(DS.Palette.soft)
                    if store.pinnedID != nil {
                        Text("#\(route.seq?.value.formatted() ?? "—") · \(route.time?.date?.formatted(.dateTime.hour().minute()) ?? "—")")
                            .font(.caption.monospaced()).foregroundStyle(DS.Palette.warn)
                        Button(String(localized: "回到实时"), systemImage: "play.fill") { store.unpin() }.frame(minHeight: 44)
                    }
                    RoutingStageView(routes: store.routes, route: route, now: store.now, seatFilter: $store.seatFilter, masked: masked)
                }.routingCard()
                HorizontalChipRow {
                    ForEach(Array(store.routes.prefix(8).enumerated()), id: \.offset) { _, recent in
                        Button { store.pin(recent) } label: {
                            Text(requestChip(recent))
                                .font(.caption.monospaced())
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(DS.Palette.hover, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                RoutingSummaryView(route: route).routingCard()
                foot
                if compact {
                    RoutingStageView(routes: store.routes, route: route, now: store.now, seatFilter: $store.seatFilter, masked: masked).seatNodes.routingCard()
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text(store.pinnedID == nil ? String(localized: "最新请求的路由经过") : String(localized: "固定请求的路由经过")).font(.headline)
                    Button(String(localized: "刷新"), systemImage: "arrow.clockwise") { restart() }.frame(minHeight: 44)
                    Text(String(format: String(localized: "策略：%@"), locale: Locale.current, String(describing: RoutePresentation.strategy(route.group?.routing)))).font(.subheadline)
                    if let reason = route.rule?.reason { Text(reason).font(.subheadline) }
                    if let error = route.error, !error.isEmpty { Text(error).foregroundStyle(DS.Palette.red) }
                    Button(String(localized: "查看尝试与步骤"), systemImage: "list.bullet.rectangle") {
                        store.pin(route)
                        showDetail = true
                    }.frame(minHeight: 44)
                    LatencyBarView(route: route)
                }.routingCard()
                ContextWaffleView(route: route).routingCard()
            } else {
                EmptyStateView(title: String(localized: "等待路由事件"), description: String(localized: "收到请求后会显示实时路由。"), systemImage: "arrow.triangle.branch")
                foot
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: String(localized: "请求列表"), subtitle: String(localized: "最近 60 条 · 最新在前"))
                if store.seatFilter != nil { Button(String(localized: "清除账号筛选"), systemImage: "xmark.circle") { store.seatFilter = nil }.frame(minHeight: 44) }
                if filteredRoutes.isEmpty { Text(String(localized: "暂无匹配请求")).foregroundStyle(DS.Palette.dim) }
                ForEach(Array(filteredRoutes.enumerated()), id: \.offset) { _, route in
                    Button { store.pin(route) } label: {
                        AgentRouteRow(route: route)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.node).stroke(store.pinnedID != nil && store.pinnedID == route.id?.value ? DS.Palette.warn : .clear))
                    }.buttonStyle(.plain).accessibilityHint(String(localized: "固定此请求并更新路由舞台"))
                }
            }.id("requests")
            RoutingAccountsView(providers: store.providers, quotas: store.usageQuotas, now: store.now, masked: $masked).routingCard()
            RoutingGroupsView(groups: store.groups).routingCard()
        }
    }
    private func requestChip(_ route: Route) -> String {
        let clock = route.time?.date?.formatted(.dateTime.hour().minute()) ?? "—"
        return "\(route.agent ?? "—") › \(route.provider ?? "—") \(clock)"
    }
    private var foot: some View {
        let counts = RoutingModel.footCounts(store.totals)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { footLabels(counts) }
            VStack(alignment: .leading, spacing: 8) { footLabels(counts) }
        }.font(.subheadline.monospacedDigit())
    }
    @ViewBuilder private func footLabels(_ counts: RoutingFootCounts) -> some View {
        Text(String(format: String(localized: "请求 %@"), locale: Locale.current, String(describing: counts.requests?.formatted() ?? "—")))
        Text(String(format: String(localized: "重路由 %@"), locale: Locale.current, String(describing: counts.rerouted?.formatted() ?? "—"))).foregroundStyle(DS.Palette.warn)
        Button {
            if let error = store.routes.first(where: RoutePresentation.failed) { store.pin(error) }
        } label: {
            Label(String(format: String(localized: "错误 %@"), locale: Locale.current, String(describing: counts.errors?.formatted() ?? "—")), systemImage: "exclamationmark.triangle")
                .foregroundStyle(DS.Palette.red).frame(minHeight: 44)
        }.disabled(!store.routes.contains(where: RoutePresentation.failed))
    }
}
