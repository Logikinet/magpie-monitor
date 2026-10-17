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
    public private(set) var isOffline = false
    public private(set) var routes: [Route] = []
    private var loaded = false
    private let sleeper: @Sendable (TimeInterval) async throws -> Void
    private var running = false

    // Keep the backoff argument source-compatible; trace retries use the API's fixed delays.
    public init(source: any TraceSource, backoff _: Backoff = Backoff(),
                sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = {
                    try await Task.sleep(for: .seconds($0))
                }) {
        self.source = source
        self.sleeper = sleeper
    }

    /// Run in the caller's task; cancel that task to stop an in-flight request or sleep.
    /// A second concurrent run is ignored.
    public func run(onEvent: @Sendable (TraceEvent) async -> Void) async {
        guard !running else { return }
        running = true
        loaded = false
        defer { running = false }
        await onEvent(.status(.connecting))
        do {
            while true {
                try Task.checkCancellation()
                do {
                    let envelope = try await source.trace(after: lastSeq, wait: loaded)
                    try Task.checkCancellation()
                    loaded = true
                    if let seq = envelope.seq?.value {
                        if seq < lastSeq { routes.removeAll() }
                        lastSeq = seq
                    }
                    if envelope.mine == false {
                        loaded = false
                        isOffline = true
                        await onEvent(.status(.backingOff(5)))
                        try await sleeper(5)
                        continue
                    }
                    isOffline = false
                    for route in envelope.routes?.elements ?? [] {
                        if let id = route.id?.value,
                           let index = routes.firstIndex(where: { $0.id?.value == id }) {
                            routes[index] = route
                        } else { routes.append(route) }
                    }
                    routes.sort { ($0.seq?.value ?? 0) < ($1.seq?.value ?? 0) }
                    routes = Array(routes.suffix(60))
                    await onEvent(.status(.live))
                    await onEvent(.envelope(TraceEnvelope(seq: envelope.seq, routes: LossyArray(routes),
                        totals: envelope.totals, mine: envelope.mine, now: envelope.now)))
                    // An unchanged/empty response must not spin if the server returns immediately.
                    if envelope.routes?.elements.isEmpty != false { try await sleeper(0.1) }
                } catch {
                    let error = MagpieError.map(error)
                    if error == .cancelled || Task.isCancelled { break }
                    if error == .unauthorized { await onEvent(.status(.unauthorized)) }
                    let delay: TimeInterval = 3
                    await onEvent(.status(.backingOff(delay)))
                    try await sleeper(delay)
                }
            }
        } catch { /* Cancellation of sleep ends the loop. */ }
        await onEvent(.status(.stopped))
    }
}
