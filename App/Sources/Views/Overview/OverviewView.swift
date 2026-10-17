import SwiftUI
import MagpieKit

@MainActor
struct OverviewView: View {
    @Environment(AppState.self) private var appState
    @State private var store = OverviewStore()

    private let columns = [GridItem(.adaptive(minimum: 230), alignment: .top)]

    var body: some View {
        Group {
            if appState.currentProfile == nil && !appState.isMockMode {
                EmptyStateView(title: "尚未选择服务器", description: "请先在设置中添加服务器配置。", systemImage: "server.rack")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.large) {
                        statusHeader
                        quotaSection
                        concurrencySection
                        listSection(
                            title: "服务", symbol: "shippingbox", error: store.containersError,
                            items: store.containers.prefix(3).map { "\($0.name) · \($0.status)" },
                            allItems: store.containers.map { "\($0.name) · \($0.status)" })
                        listSection(
                            title: "端口", symbol: "point.3.connected.trianglepath.dotted", error: store.portsError,
                            items: store.ports.prefix(3).map { "\($0.address):\($0.port) · \($0.processName ?? "未知进程")" },
                            allItems: store.ports.map { "\($0.address):\($0.port) · \($0.processName ?? "未知进程")" })
                        listSection(
                            title: "系统服务", symbol: "gearshape.2", error: store.unitsError,
                            items: store.units.prefix(3).map { "\($0.name) · \($0.active)" },
                            allItems: store.units.map { "\($0.name) · \($0.active) · \($0.description)" })
                        listSection(
                            title: "高占用进程", symbol: "cpu", error: store.processesError,
                            items: store.processes.prefix(3).map { "\($0.command) · CPU \($0.cpu.formatted())%" },
                            allItems: store.processes.map {
                                "PID \($0.pid) · \($0.command) · CPU \($0.cpu.formatted())% · 内存 \($0.memory.formatted())%"
                            })
                    }
                    .padding(DS.Spacing.medium)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await store.refresh(appState: appState) }
            }
        }
        .task(
            id: RefreshContext(
                profile: appState.currentProfile,
                isMockMode: appState.isMockMode,
                isActive: appState.isActive
            )
        ) {
            guard appState.isActive else { return }
            await store.refresh(appState: appState)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(appState.refreshInterval)) } catch { return }
                guard appState.isActive else { return }
                await store.refresh(appState: appState)
            }
        }
    }

    private var statusHeader: some View {
        HStack(alignment: .center, spacing: DS.Spacing.medium) {
            StatusBadge(
                kind: store.gatewayError == nil && store.version != nil ? .ok : .error,
                text: store.gatewayError == nil && store.version != nil ? "网关在线" : "网关离线")
            if let version = store.version {
                Text("版本 \(version)").font(.subheadline.monospaced()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let updated = store.lastUpdated {
                Text(updated, style: .relative).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityLabel("上次更新")
            }
            if store.isRefreshing { ProgressView().accessibilityLabel("正在刷新") }
        }
        .padding(.vertical, DS.Spacing.small)
        .accessibilityElement(children: .combine)
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.mediumSmall) {
            SectionHeader(title: "配额")
            if let error = store.quotaError {
                sectionError(error)
            } else if store.quotas.isEmpty {
                EmptyStateView(title: "暂无配额数据", description: "服务器未提供可显示的 5 小时或每周配额。", systemImage: "gauge")
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Spacing.mediumSmall) {
                    ForEach(store.quotas) { quota in
                        QuotaGauge(title: "\(quota.provider) · \(quota.window)", used: quota.used, limit: quota.limit)
                    }
                }
            }
        }
    }

    private var concurrencySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.mediumSmall) {
            SectionHeader(title: "并发")
            if let error = store.concurrencyError {
                sectionError(error)
            } else if let value = store.concurrency {
                LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Spacing.mediumSmall) {
                    MetricCard(
                        title: "活动请求", value: "\(value.requests?.value ?? value.active?.elements.count ?? 0)",
                        systemImage: "arrow.left.arrow.right")
                    MetricCard(title: "等待中", value: "\(value.waiting?.value ?? 0)", systemImage: "hourglass")
                    MetricCard(title: "工具运行", value: "\(value.tools?.value ?? 0)", systemImage: "wrench.and.screwdriver")
                    ForEach(value.data?.keys.sorted() ?? [], id: \.self) { name in
                        if let lane = value.data?[name] {
                            MetricCard(
                                title: name, value: "\(lane.busy?.value ?? 0) / \(lane.limit?.value ?? 0)",
                                caption: "等待 \(lane.waiting?.value ?? 0)", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        }
                    }
                }
            } else {
                EmptyStateView(title: "暂无并发数据", systemImage: "arrow.left.arrow.right")
            }
        }
    }

    @ViewBuilder
    private func listSection(title: String, symbol: String, error: String?, items: [String], allItems: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            HStack {
                SectionHeader(title: title)
                Spacer()
                NavigationLink("查看全部") { OverviewDetailView(title: title, items: allItems, error: error) }
                    .font(.subheadline)
                    .accessibilityHint("打开全部\(title)列表")
            }
            if let error {
                sectionError(error)
            } else if items.isEmpty {
                Text("暂无数据").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, DS.Spacing.small)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: DS.Spacing.small) {
                            Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
                            Text(item).font(.subheadline).lineLimit(2).textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, DS.Spacing.small)
                        if index < items.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, DS.Spacing.medium)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
        }
    }

    private func sectionError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            if message.localizedCaseInsensitiveContains("Share on local network") {
                Text("请在 magpie 设置中允许局域网访问。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("重试") { Task { await store.refresh(appState: appState) } }
                .font(.subheadline.weight(.medium)).frame(minHeight: 44)
        }
        .padding(DS.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

private struct OverviewDetailView: View {
    let title: String
    let items: [String]
    let error: String?

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("无法读取\(title)", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if items.isEmpty {
                ContentUnavailableView("暂无\(title)", systemImage: "tray")
            } else {
                List(items, id: \.self) { item in Text(item).textSelection(.enabled) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
