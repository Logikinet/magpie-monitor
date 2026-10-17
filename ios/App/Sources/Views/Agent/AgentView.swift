import SwiftUI
import MagpieKit

@MainActor
struct AgentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = AgentStore()
    @State private var visible = false
    @State private var tab = "routing"
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
                    Picker("Agent 页面", selection: $tab) {
                        Text("路由").tag("routing")
                        Text("用量").tag("usage")
                        Text("服务商").tag("providers")
                        Text("运行时").tag("runtimes")
                    }.pickerStyle(.segmented)
                    if store.configurationMissing {
                        EmptyStateView(title: "配置实时路由", description: "请在设置中填写 Web 地址和 runtime key。", systemImage: "point.3.connected.trianglepath.dotted")
                    } else {
                        StatusBadge(kind: store.authFailed ? .error : (store.status == .live ? .ok : .neutral), text: store.statusText)
                        if store.authFailed { Text("认证失败，请在设置中更新 runtime key。").foregroundStyle(DS.Palette.red) }
                        switch tab {
                        case "usage": quotas
                        case "providers": EmptyStateView(title: "服务商与模型", description: "服务商管理将在后续版本加入。", systemImage: "server.rack")
                        case "runtimes": EmptyStateView(title: "运行时与环境", description: "连接 collector 后可查看运行环境。", systemImage: "terminal")
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
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(store.routes.prefix(8).enumerated()), id: \.offset) { _, recent in
                            Button { store.pin(recent) } label: {
                                Text("\(recent.agent ?? "—") › \(recent.provider ?? "—") \(recent.time?.date?.formatted(.dateTime.hour().minute()) ?? "—")")
                                    .font(.caption.monospaced()).padding(12).frame(minHeight: 44)
                                    .background(DS.Palette.hover, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(route.group?.name ?? route.group?.id ?? "—") · 路由组").font(.headline)
                    Text("\((route.order?.elements ?? []).filter { $0.fallback != true }.count) 个候选节点").font(.caption).foregroundStyle(DS.Palette.soft)
                    if store.pinnedID != nil {
                        Text("#\(route.seq?.value.formatted() ?? "—") · \(route.time?.date?.formatted(.dateTime.hour().minute()) ?? "—")")
                            .font(.caption.monospaced()).foregroundStyle(DS.Palette.warn)
                        Button("回到实时", systemImage: "play.fill") { store.unpin() }.frame(minHeight: 44)
                    }
                    RoutingStageView(routes: store.routes, route: route, now: store.now, seatFilter: $store.seatFilter, masked: masked)
                }.routingCard()
                RoutingSummaryView(route: route).routingCard()
                foot
                VStack(alignment: .leading, spacing: 16) {
                    Text(store.pinnedID == nil ? "最新请求的路由经过" : "固定请求的路由经过").font(.headline)
                    Button("刷新", systemImage: "arrow.clockwise") { restart() }.frame(minHeight: 44)
                    Text("策略：\(RoutePresentation.strategy(route.group?.routing))").font(.subheadline)
                    if let reason = route.rule?.reason { Text(reason).font(.subheadline) }
                    if let error = route.error, !error.isEmpty { Text(error).foregroundStyle(DS.Palette.red) }
                    Button("查看尝试与步骤", systemImage: "list.bullet.rectangle") {
                        store.pin(route)
                        showDetail = true
                    }.frame(minHeight: 44)
                    LatencyBarView(route: route)
                }.routingCard()
                ContextWaffleView(route: route).routingCard()
            } else {
                EmptyStateView(title: "等待路由事件", description: "收到请求后会显示实时路由。", systemImage: "arrow.triangle.branch")
                foot
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "请求列表", subtitle: "最近 60 条 · 最新在前")
                if store.seatFilter != nil { Button("清除账号筛选", systemImage: "xmark.circle") { store.seatFilter = nil }.frame(minHeight: 44) }
                if filteredRoutes.isEmpty { Text("暂无匹配请求").foregroundStyle(DS.Palette.dim) }
                ForEach(Array(filteredRoutes.enumerated()), id: \.offset) { _, route in
                    Button { store.pin(route) } label: {
                        AgentRouteRow(route: route)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.node).stroke(store.pinnedID != nil && store.pinnedID == route.id?.value ? DS.Palette.warn : .clear))
                    }.buttonStyle(.plain).accessibilityHint("固定此请求并更新路由舞台")
                }
            }.id("requests")
            RoutingAccountsView(providers: store.providers, quotas: store.usageQuotas, now: store.now, masked: $masked).routingCard()
            RoutingGroupsView(groups: store.groups).routingCard()
        }
    }
    private var foot: some View {
        let counts = RoutingModel.footCounts(store.totals)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { footLabels(counts) }
            VStack(alignment: .leading, spacing: 8) { footLabels(counts) }
        }.font(.subheadline.monospacedDigit())
    }
    @ViewBuilder private func footLabels(_ counts: RoutingFootCounts) -> some View {
        Text("请求 \(counts.requests?.formatted() ?? "—")")
        Text("重路由 \(counts.rerouted?.formatted() ?? "—")").foregroundStyle(DS.Palette.warn)
        Button {
            if let error = store.routes.first(where: RoutePresentation.failed) { store.pin(error) }
        } label: {
            Label("错误 \(counts.errors?.formatted() ?? "—")", systemImage: "exclamationmark.triangle")
                .foregroundStyle(DS.Palette.red).frame(minHeight: 44)
        }.disabled(!store.routes.contains(where: RoutePresentation.failed))
    }
    private var quotas: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "配额")
            if let error = store.quotaError { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline) }
            if store.cards.isEmpty { Text("暂无配额卡片").foregroundStyle(DS.Palette.dim) }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(store.cards.enumerated()), id: \.offset) { _, card in AgentQuotaCardView(card: card) }
            }
        }
    }
}
