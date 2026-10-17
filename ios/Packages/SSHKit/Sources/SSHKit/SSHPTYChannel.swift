import Foundation
@preconcurrency import Citadel
import NIOCore
@preconcurrency import NIOSSH
import MagpieKit

public actor SSHPTYChannel {
    public nonisolated let output: AsyncStream<[UInt8]>
    /// AsyncStream finishes on EOF or failure; inspect this to distinguish failure.
    public private(set) var terminalError: MagpieError?
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private var client: SSHClient?
    private var writer: TTYStdinWriter?
    private var worker: Task<Void, Never>?
    private var ready: CheckedContinuation<Void, Error>?
    private var closed = false

    private init(client: SSHClient) {
        let stream = AsyncStream<[UInt8]>.makeStream()
        output = stream.stream
        continuation = stream.continuation
        self.client = client
        continuation.onTermination = { [weak self] _ in
            Task { await self?.close() }
        }
    }

    @available(macOS 15, *)
    static func open(config: SSHConfig, pin: String, command: String, cols: Int, rows: Int) async throws -> SSHPTYChannel {
        guard cols > 0, rows > 0, !command.contains("\0") else {
            throw MagpieError.sshFailed("终端尺寸或命令无效。")
        }
        let (client, _) = try await SSHClientFactory.connect(config: config, pin: pin)
        let channel = SSHPTYChannel(client: client)
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try await channel.start(command: command, cols: cols, rows: rows)
                try Task.checkCancellation()
                return channel
            } catch {
                await channel.close()
                throw SSHClientFactory.map(error)
            }
        } onCancel: {
            Task { await channel.close() }
        }
    }

    @available(macOS 15, *)
    private func start(command: String, cols: Int, rows: Int) async throws {
        guard !closed else { throw MagpieError.cancelled }
        try await withCheckedThrowingContinuation { completion in
            ready = completion
            worker = Task { await pump(command: command, cols: cols, rows: rows) }
        }
    }

    @available(macOS 15, *)
    private func pump(command: String, cols: Int, rows: Int) async {
        guard let client, !closed else { return }
        do {
            try await client.withPTY(.init(
                wantReply: true, term: "xterm-256color",
                terminalCharacterWidth: cols, terminalRowHeight: rows,
                terminalPixelWidth: 0, terminalPixelHeight: 0,
                terminalModes: .init([:])
            )) { inbound, outbound in
                try await self.install(outbound)
                // withPTY starts a shell, not an exec request. Quote the command for
                // the login shell and exit it when the interactive command finishes.
                let quoted = "'" + command.replacingOccurrences(of: "'", with: "'\\''") + "'"
                try await outbound.write(ByteBuffer(string: "exec sh -c \(quoted)\n"))
                await self.didOpen()
                for try await chunk in inbound {
                    try Task.checkCancellation()
                    switch chunk {
                    case .stdout(let buffer), .stderr(let buffer):
                        await self.receive(Array(buffer.readableBytesView))
                    }
                }
            }
        } catch {
            if !closed { terminalError = SSHClientFactory.map(error) }
        }
        finishOpening(error: terminalError ?? .sshFailed("终端已关闭。"))
        await close()
    }

    private func install(_ writer: TTYStdinWriter) throws {
        guard !closed else { throw MagpieError.cancelled }
        self.writer = writer
    }

    private func didOpen() {
        let completion = ready
        ready = nil
        completion?.resume()
    }

    private func receive(_ bytes: [UInt8]) {
        if !closed { continuation.yield(bytes) }
    }

    public func send(_ bytes: [UInt8]) async throws {
        try Task.checkCancellation()
        guard let writer, !closed else { throw MagpieError.sshFailed("终端未连接。") }
        do { try await writer.write(ByteBuffer(bytes: bytes)) }
        catch { throw SSHClientFactory.map(error) }
    }

    public func resize(cols: Int, rows: Int) async throws {
        guard cols > 0, rows > 0 else { throw MagpieError.sshFailed("终端尺寸无效。") }
        guard let writer, !closed else { throw MagpieError.sshFailed("终端未连接。") }
        do { try await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0) }
        catch { throw SSHClientFactory.map(error) }
    }

    public func close() async {
        guard !closed else { return }
        closed = true
        finishOpening(error: .cancelled)
        writer = nil
        worker?.cancel()
        worker = nil
        continuation.finish()
        let previous = client
        client = nil
        try? await previous?.close()
    }

    private func finishOpening(error: MagpieError) {
        let completion = ready
        ready = nil
        completion?.resume(throwing: error)
    }
}
