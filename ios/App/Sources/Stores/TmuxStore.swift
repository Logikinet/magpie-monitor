import Foundation
import Observation
import MagpieKit
import SSHKit

@MainActor @Observable
final class TmuxStore {
    enum ConnectionState: String {
        var title: String {
            switch self {
            case .connecting: String(localized: "连接中")
            case .connected: String(localized: "已连接")
            case .disconnected: String(localized: "已断开")
            }
        }
        case connecting
        case connected
        case disconnected
    }

    private(set) var collectorTopology: CollectorRecord?
    private(set) var sessions: [TmuxSession] = []
    private(set) var isLoading = false
    private(set) var state: ConnectionState = .disconnected
    private(set) var channel: SSHPTYChannel?
    private(set) var error: String?
    private(set) var terminalID = UUID()
    var selectedSession = ""
    private var runner: (any SSHRunning)?
    private var attempt = UUID()
    private var target: String?
    private var createsSession = false

    func refresh(appState: AppState, useCollector: Bool = true) async {
        guard appState.isActive, !isLoading else { return }
        if useCollector, let client = appState.makeCollectorClient() {
            isLoading = true
            do {
                collectorTopology = try await client.tmux()
                error = nil
                isLoading = false
                return
            } catch { self.error = ErrorMessages.chinese(for: error) }
            isLoading = false
        }
        collectorTopology = nil
        guard !appState.isMockMode else { return }
        isLoading = true
        let token = attempt
        defer { if token == attempt { isLoading = false } }
        do {
            let runner = try await appState.makeOverviewSSHRunner()
            do {
                let output = try await runner.run(SSHCommands.tmuxSessions, idempotent: true)
                await runner.disconnect()
                guard token == attempt, !Task.isCancelled else { return }
                sessions = SSHOutputParser.parseTmuxSessions(output)
                if !sessions.contains(where: { $0.name == selectedSession }) { selectedSession = "" }
                error = nil
            } catch {
                await runner.disconnect()
                throw error
            }
        } catch {
            guard token == attempt, !Task.isCancelled else { return }
            self.error = message(error, fallback: String(localized: "无法读取会话；若尚无 tmux 服务，可选择新建会话。"))
        }
    }

    func connect(appState: AppState, reconnect: Bool = false) async {
        guard !appState.isMockMode, appState.isActive, state == .disconnected else { return }
        if !reconnect || target == nil {
            createsSession = selectedSession.isEmpty
            target = createsSession ? "magpie-\(UUID().uuidString.prefix(8).lowercased())" : selectedSession
        }
        guard let target else { return }
        let token = UUID()
        attempt = token
        state = .connecting
        error = nil
        terminalID = UUID()
        do {
            let runner = try await appState.makeOverviewSSHRunner()
            guard token == attempt, !Task.isCancelled else {
                await runner.disconnect()
                return
            }
            self.runner = runner
            guard let connection = runner as? SSHConnection else {
                throw MagpieError.sshFailed(String(localized: "当前连接不支持交互终端。"))
            }
            // Shell quoting protects remote session names, including spaces and apostrophes.
            let quoted = "'" + target.replacingOccurrences(of: "'", with: "'\\''") + "'"
            let command =
                createsSession
                ? "tmux new-session -A -s \(quoted)"
                : "tmux attach-session -t '=\(target.replacingOccurrences(of: "'", with: "'\\''"))'"
            let channel = try await connection.openPTY(command: command)
            guard token == attempt, !Task.isCancelled else {
                await channel.close()
                await runner.disconnect()
                return
            }
            self.channel = channel
            state = .connected
        } catch {
            guard token == attempt else { return }
            self.error = message(error, fallback: String(localized: "终端连接失败，请检查 SSH 和 tmux 后重连。"))
            disconnect()
        }
    }

    func ended(_ channel: SSHPTYChannel, error: Error?) {
        guard self.channel === channel else { return }
        self.error = error.map { message($0, fallback: String(localized: "终端连接已中断，请手动重连。")) }
        disconnect()
    }

    func disconnect() {
        attempt = UUID()
        let previousChannel = channel
        let previousRunner = runner
        channel = nil
        runner = nil
        state = .disconnected
        isLoading = false
        Task {
            await previousChannel?.close()
            await previousRunner?.disconnect()
        }
    }

    func reset() {
        disconnect()
        collectorTopology = nil
        sessions = []
        selectedSession = ""
        target = nil
        error = nil
        terminalID = UUID()
    }

    private func message(_ error: Error, fallback: String) -> String {
        (error as? MagpieError).map { ErrorMessages.chinese(for: $0) } ?? fallback
    }
}
