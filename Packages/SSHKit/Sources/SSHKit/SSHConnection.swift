import Foundation
@preconcurrency import Citadel
import MagpieKit

public actor SSHConnection: SSHRunning {
    private var client: SSHClient?
    private var config: SSHConfig?
    private var fingerprint: String?
    private var generation = UUID()
    private var terminals: [SSHPTYChannel] = []

    public init() {}

    /// Persist the returned fingerprint in Keychain before the next connection.
    @discardableResult
    public func connect(config: SSHConfig, pinnedFingerprint: String? = nil) async throws -> String {
        let previous = detach()
        let attempt = generation
        await close(previous)
        guard generation == attempt else { throw MagpieError.cancelled }
        let (connected, observed) = try await SSHClientFactory.connect(config: config, pin: pinnedFingerprint)
        guard generation == attempt else {
            try? await connected.close()
            throw MagpieError.cancelled
        }
        client = connected
        self.config = config
        fingerprint = observed
        return observed
    }

    public func run(_ command: String, idempotent: Bool = false) async throws -> String {
        try Task.checkCancellation()
        guard let client, let config else { throw MagpieError.sshFailed("请先连接 SSH。") }
        let attempt = generation
        do {
            return try await execute(command, on: client)
        } catch {
            // Nonzero exit status and other command failures must never cause a replay.
            guard idempotent, !client.isConnected, generation == attempt, !Task.isCancelled,
                  !(error is SSHClient.CommandFailed) else { throw SSHClientFactory.map(error) }
            generation = UUID()
            let retry = generation
            let (replacement, observed) = try await SSHClientFactory.connect(config: config, pin: fingerprint)
            guard generation == retry else {
                try? await replacement.close()
                throw MagpieError.cancelled
            }
            self.client = replacement
            fingerprint = observed
            do { return try await execute(command, on: replacement) }
            catch { throw SSHClientFactory.map(error) }
        }
    }

    private func execute(_ command: String, on client: SSHClient) async throws -> String {
        let buffer = try await client.executeCommand(command, maxResponseSize: 8 * 1024 * 1024, mergeStreams: true)
        try Task.checkCancellation()
        return String(decoding: buffer.readableBytesView, as: UTF8.self)
    }

    /// A dedicated transport lets closing a terminal release its channel immediately.
    /// PTYs never reconnect automatically. Citadel 0.12.1 requires macOS 15 for withPTY.
    public func openPTY(command: String, cols: Int = 80, rows: Int = 24) async throws -> SSHPTYChannel {
        guard #available(macOS 15, *) else {
            throw MagpieError.sshFailed("交互终端需要 macOS 15 或更高版本。")
        }
        guard let config, let fingerprint else { throw MagpieError.sshFailed("请先连接 SSH。") }
        let attempt = generation
        let channel = try await SSHPTYChannel.open(config: config, pin: fingerprint, command: command, cols: cols, rows: rows)
        guard generation == attempt else {
            await channel.close()
            throw MagpieError.cancelled
        }
        terminals.append(channel)
        return channel
    }

    public func disconnect() async {
        let previous = detach()
        await close(previous)
    }

    private func detach() -> (SSHClient?, [SSHPTYChannel]) {
        generation = UUID()
        let previous = (client, terminals)
        client = nil
        config = nil
        fingerprint = nil
        terminals = []
        return previous
    }

    private func close(_ previous: (SSHClient?, [SSHPTYChannel])) async {
        for channel in previous.1 { await channel.close() }
        try? await previous.0?.close()
    }
}
