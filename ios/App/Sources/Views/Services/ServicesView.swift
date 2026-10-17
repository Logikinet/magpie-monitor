import SwiftUI

@MainActor
struct ServicesView: View {
    @Environment(AppState.self) private var appState
    @State private var store = ServicesStore()
    @State private var category: ServicesCategory = .containers
    @State private var searchText = ""
    @State private var pendingOperation: ServiceOperation?
    @State private var isConfirming = false

    private var entries: [ServiceEntry] {
        let items = store.entries(for: category)
        guard !searchText.isEmpty else { return items }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.detail.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                Picker("服务类型", selection: $category) {
                    ForEach(ServicesCategory.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if category == .systemd {
                Section {
                    Toggle("systemctl 使用 sudo -n", isOn: $store.useSudo)
                    Text("仅保存于当前服务器配置。sudo -n 不会等待输入密码。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if appState.isMockMode {
                Section {
                    Label("模拟数据；服务操作仅在本机模拟，不会连接 SSH。", systemImage: "play.rectangle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let message = category == .containers ? store.containersError : store.unitsError,
                entries.isEmpty
            {
                Section {
                    ContentUnavailableView {
                        Label("无法读取服务", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") { Task { await store.refresh(appState: appState) } }
                    }
                }
            } else if entries.isEmpty {
                Section {
                    EmptyStateView(
                        title: searchText.isEmpty ? "暂无\(category.rawValue)" : "没有匹配的服务",
                        description: searchText.isEmpty ? "下拉刷新以重新读取服务器状态。" : "尝试其他名称或关键词。",
                        systemImage: category == .containers ? "shippingbox" : "gearshape.2"
                    )
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        ServiceRow(entry: entry, isLoading: store.inFlightIDs.contains(entry.id))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                actionButton(.stop, for: entry, role: .destructive)
                                actionButton(.restart, for: entry)
                                actionButton(.start, for: entry)
                            }
                            .contextMenu {
                                actionButton(.start, for: entry)
                                actionButton(.stop, for: entry, role: .destructive)
                                actionButton(.restart, for: entry)
                            }
                    }
                } header: {
                    HStack {
                        Text(category.rawValue)
                        Spacer()
                        if store.isRefreshing {
                            ProgressView().controlSize(.small).accessibilityLabel("正在刷新")
                        } else if let updated = store.lastUpdated {
                            Text(updated, style: .relative).textCase(nil)
                        }
                    }
                }
            }

            if let message = category == .containers ? store.containersError : store.unitsError,
                !entries.isEmpty
            {
                Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }

            if let notice = store.notice {
                Section { Label(notice, systemImage: "checkmark.circle").foregroundStyle(.secondary).textSelection(.enabled) }
            }
            if let error = store.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).fixedSize(
                        horizontal: false, vertical: true)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "搜索容器或服务")
        .refreshable { await store.refresh(appState: appState) }
        .navigationTitle("服务")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refresh(appState: appState) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新服务")
                .disabled(store.isRefreshing)
            }
        }
        .confirmationDialog(
            "确认\(pendingOperation?.action.rawValue ?? "服务操作")？",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            if let operation = pendingOperation {
                if operation.action == .stop {
                    Button(operation.action.rawValue, role: .destructive) { execute(operation) }
                } else {
                    Button(operation.action.rawValue) { execute(operation) }
                }
            }
            Button("取消", role: .cancel) { pendingOperation = nil }
        } message: {
            if let operation = pendingOperation {
                Text("\(operation.entry.name)\n将执行：\n\(operation.command)")
            }
        }
        .task(id: "\(appState.currentProfile?.id.uuidString ?? "mock")-\(appState.isMockMode)-\(appState.isActive)") {
            guard appState.isActive else { return }
            store.loadPreference(appState: appState)
            await store.refresh(appState: appState)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(appState.refreshInterval)) } catch { return }
                guard appState.isActive else { return }
                await store.refresh(appState: appState)
            }
        }
    }

    private func actionButton(_ action: ServiceAction, for entry: ServiceEntry, role: ButtonRole? = nil) -> some View {
        Button(role: role) {
            if let operation = store.prepareOperation(for: entry, action: action) {
                pendingOperation = operation
                isConfirming = true
            }
        } label: {
            Label(action.rawValue, systemImage: symbol(for: action))
        }
        .disabled(store.inFlightIDs.contains(entry.id))
    }

    private func symbol(for action: ServiceAction) -> String {
        switch action {
        case .start: "play.fill"
        case .stop: "stop.fill"
        case .restart: "arrow.clockwise"
        }
    }

    private func execute(_ operation: ServiceOperation) {
        pendingOperation = nil
        Task { await store.perform(operation, appState: appState) }
    }
}

private struct ServiceRow: View {
    let entry: ServiceEntry
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.small) {
                Text(entry.name)
                    .font(.headline)
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Spacing.small)
                if isLoading {
                    ProgressView().controlSize(.small).accessibilityLabel("正在操作")
                } else {
                    StatusBadge(kind: entry.status.kind, text: entry.status.title)
                }
            }
            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DS.Spacing.xSmall)
        .accessibilityElement(children: .combine)
    }
}
