import SwiftUI
import MagpieKit

@MainActor
struct AgentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AgentStore()
    @State private var visible = false
    @State private var selectedRoute: Route?
    private let columns = [GridItem(.adaptive(minimum: 230), alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.large) {
                if store.configurationMissing {
                    EmptyStateView(
                        title: "配置实时路由", description: "请在设置中填写服务器的 Web 地址和 runtime key。Web 地址使用 magpie Web 界面的端口；密钥可从 Web 访问链接获取。",
                        systemImage: "point.3.connected.trianglepath.dotted")
                } else {
                    StatusBadge(kind: store.authFailed ? .error : (store.status == .live ? .ok : .neutral), text: store.statusText)
                        .padding(DS.Spacing.small)
                        .background(.background.secondary, in: Capsule())
                    if store.authFailed {
                        Label("runtime key 已失效，请在设置中更新。建议在 magpie 设置固定 MAGPIE_WEB_KEY。", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(.red)
                    }
                    totals
                    concurrency
                    quotas
                    SectionHeader(title: "路由流", subtitle: "最近 200 条 · 最新在前")
                    if store.routes.isEmpty {
                        EmptyStateView(title: "等待路由事件", description: "收到请求后会显示实时路由。", systemImage: "arrow.triangle.branch")
                    }
                    ForEach(Array(store.routes.enumerated()), id: \.offset) { _, route in
                        Button {
                            selectedRoute = route
                        } label: {
                            AgentRouteRow(route: route)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("打开路由详情和候选顺序")
                    }
                }
            }
            .padding(DS.Spacing.medium)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            visible = true
            restart()
        }
        .onDisappear {
            visible = false
            store.stop()
            selectedRoute = nil
        }
        .onChange(of: scenePhase) { _, _ in restart() }
        .onChange(of: appState.isActive) { _, _ in restart() }
        .onChange(of: appState.currentProfile) { _, _ in
            selectedRoute = nil
            restart()
        }
        .onChange(of: appState.isMockMode) { _, _ in
            selectedRoute = nil
            restart()
        }
        .sheet(isPresented: Binding(get: { selectedRoute != nil }, set: { if !$0 { selectedRoute = nil } })) {
            if let selectedRoute { AgentRouteDetailView(route: selectedRoute) }
        }
    }

    private func restart() {
        if visible && scenePhase == .active && appState.isActive { store.start(appState: appState) } else { store.stop() }
    }

    private var totals: some View {
        LazyVGrid(columns: columns, spacing: DS.Spacing.mediumSmall) {
            MetricCard(title: "请求", value: store.totals?.requests?.value.formatted() ?? "—", systemImage: "arrow.left.arrow.right")
            MetricCard(title: "重新路由", value: store.totals?.rerouted?.value.formatted() ?? "—", systemImage: "arrow.triangle.branch")
            MetricCard(title: "错误", value: store.totals?.errors?.value.formatted() ?? "—", systemImage: "exclamationmark.triangle")
        }
    }

    private var concurrency: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.mediumSmall) {
            SectionHeader(title: "并发通道")
            if let error = store.concurrencyError { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline) }
            if let lanes = store.concurrency?.data, !lanes.isEmpty {
                ForEach(lanes.keys.sorted(), id: \.self) { name in
                    if let lane = lanes[name] {
                        VStack(alignment: .leading, spacing: DS.Spacing.small) {
                            Text(name).font(.headline.monospaced()).textSelection(.enabled)
                            Text(
                                """
                                忙碌 \(lane.busy?.value.formatted() ?? "—") · \
                                等待 \(lane.waiting?.value.formatted() ?? "—") · \
                                上限 \(lane.limit?.value.formatted() ?? "—")
                                """
                            )
                            .font(.subheadline).monospacedDigit()
                            if let limit = lane.limit?.value, limit > 0 {
                                ProgressView(value: min(max(Double(lane.busy?.value ?? 0), 0), Double(limit)), total: Double(limit))
                                    .accessibilityLabel("\(name)忙碌容量")
                                    .accessibilityValue("忙碌 \(lane.busy?.value ?? 0)，上限 \(limit)，等待 \(lane.waiting?.value ?? 0)")
                            } else {
                                Text("未设置并发上限").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(DS.Spacing.medium)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: DS.Radius.card))
                    }
                }
            } else {
                Text("暂无并发数据").foregroundStyle(.secondary)
            }
        }
    }

    private var quotas: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.mediumSmall) {
            SectionHeader(title: "配额")
            if let error = store.quotaError { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline) }
            if store.cards.isEmpty { Text("暂无配额卡片").foregroundStyle(.secondary) }
            LazyVGrid(columns: columns, spacing: DS.Spacing.mediumSmall) {
                ForEach(Array(store.cards.enumerated()), id: \.offset) { _, card in AgentQuotaCardView(card: card) }
            }
        }
    }
}
