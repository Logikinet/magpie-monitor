import SwiftUI

@MainActor
struct TmuxView: View {
    @Environment(AppState.self) private var appState
    @State private var store = TmuxStore()

    private var contextID: String {
        "\(appState.currentProfile?.id.uuidString ?? "none")-\(appState.isMockMode)"
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.small) {
                    HStack {
                        StatusBadge(kind: statusKind, text: store.state.rawValue)
                        Spacer()
                        if store.isLoading { ProgressView().accessibilityLabel("正在读取会话") }
                    }
                    if appState.isMockMode {
                        Text("终端演示 · 连接已停用")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Picker("会话", selection: $store.selectedSession) {
                            Text("新建会话").tag("")
                            ForEach(store.sessions, id: \.name) { session in
                                Text("\(session.name) · \(session.windows) 个窗口").tag(session.name)
                            }
                        }
                        .disabled(store.state != .disconnected)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: DS.Spacing.small) { controls }
                        VStack(alignment: .leading, spacing: DS.Spacing.small) { controls }
                    }
                    .disabled(appState.isMockMode || !appState.isActive || appState.currentProfile == nil)
                    if let error = store.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DS.Spacing.medium)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(.background.secondary)
            TerminalBridge(channel: store.channel, isDemo: appState.isMockMode) { channel, error in
                store.ended(channel, error: error)
            }
            .id(store.terminalID)
            .overlay {
                if !appState.isMockMode, store.channel == nil {
                    EmptyStateView(title: store.state == .connecting ? "正在连接终端" : "选择会话后连接",
                                   description: "连接中断后，请点按重连。", systemImage: "terminal")
                        .allowsHitTesting(false)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: contextID) {
            store.reset()
            await store.refresh(appState: appState)
        }
        .onChange(of: appState.isActive) { _, active in
            if !active { store.disconnect() }
        }
        .onDisappear { store.disconnect() }
    }

    @ViewBuilder private var controls: some View {
        if store.state == .disconnected {
            Button("连接", systemImage: "terminal") {
                Task { await store.connect(appState: appState) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isLoading)
            Button("重连", systemImage: "arrow.clockwise") {
                Task { await store.connect(appState: appState, reconnect: true) }
            }
            .buttonStyle(.bordered)
            .disabled(store.isLoading)
        } else {
            Button("断开", systemImage: "xmark.circle") { store.disconnect() }
                .buttonStyle(.bordered)
        }
        Button("刷新会话", systemImage: "arrow.triangle.2.circlepath") {
            Task { await store.refresh(appState: appState) }
        }
        .buttonStyle(.bordered)
        .disabled(store.isLoading || store.state != .disconnected)
    }

    private var statusKind: DS.StatusKind {
        switch store.state {
        case .connecting: .warning
        case .connected: .ok
        case .disconnected: .neutral
        }
    }
}
