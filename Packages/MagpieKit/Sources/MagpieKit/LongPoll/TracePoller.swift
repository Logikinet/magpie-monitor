import Foundation

public protocol TraceSource: Sendable {
    func trace(after: Int, wait: Bool) async throws -> TraceEnvelope
}

public enum PollStatus: Sendable, Equatable {
    case connecting, live, backingOff(TimeInterval), unauthorized, stopped
}

public enum TraceEvent: Sendable {
    case envelope(TraceEnvelope)
    case status(PollStatus)
}

public actor TracePoller {
    public private(set) var lastSeq = 0
    private let source: any TraceSource
    private var backoff: Backoff
    private let sleeper: @Sendable (TimeInterval) async throws -> Void
    private var running = false

    public init(source: any TraceSource, backoff: Backoff = Backoff(),
                sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = {
                    try await Task.sleep(for: .seconds($0))
                }) {
        self.source = source
        self.backoff = backoff
        self.sleeper = sleeper
    }

    /// Run in the caller's task; cancel that task to stop an in-flight request or sleep.
    /// A second concurrent run is ignored.
    public func run(onEvent: @Sendable (TraceEvent) async -> Void) async {
        guard !running else { return }
        running = true
        defer { running = false }
        await onEvent(.status(.connecting))
        do {
            while true {
                try Task.checkCancellation()
                do {
                    let envelope = try await source.trace(after: lastSeq, wait: true)
                    try Task.checkCancellation()
                    if let seq = envelope.seq?.value {
                        lastSeq = seq < lastSeq ? 0 : max(lastSeq, seq)
                    }
                    backoff.reset()
                    await onEvent(.status(.live))
                    await onEvent(.envelope(envelope))
                    // An unchanged/empty response must not spin if the server returns immediately.
                    if envelope.routes?.elements.isEmpty != false { try await sleeper(0.1) }
                } catch {
                    let error = MagpieError.map(error)
                    if error == .cancelled || Task.isCancelled { break }
                    if error == .timeout {
                        try await sleeper(0.1)
                        continue
                    }
                    if error == .unauthorized { await onEvent(.status(.unauthorized)) }
                    let delay = backoff.next()
                    await onEvent(.status(.backingOff(delay)))
                    try await sleeper(delay)
                }
            }
        } catch { /* Cancellation of sleep ends the loop. */ }
        await onEvent(.status(.stopped))
    }
}
