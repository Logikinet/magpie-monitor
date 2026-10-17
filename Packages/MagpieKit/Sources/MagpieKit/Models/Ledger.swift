import Foundation

public struct Ledger: Decodable {
    public let callerKeys: LossyArray<CallerKeyGroup>?
    public let period: String?
    public let rows: LossyArray<LedgerRow>
    public let offset: FlexibleInt?
    public let total: FlexibleInt?
    public let bucket: String?
    public let series: LossyArray<SeriesPoint>?
}

/// A flattened usage.Record plus the query-time fields added by usage.Row.
public struct LedgerRow: Decodable {
    public let operation: String?
    public let routeID: FlexibleInt?
    public let time: MagpieDate?
    public let agent: String?
    public let provider: String?
    public let host: String?
    public let providerKeyID: String?
    public let providerKeyName: String?
    public let providerAccount: String?
    public let callerKeyID: String?
    public let callerKeyName: String?
    public let sessionProvider: String?
    public let sessionAccount: String?
    public let sessionOfficialLogin: Bool?
    public let model: String?
    public let requested: String?
    public let served: String?
    public let upstream: String?
    public let input: FlexibleInt?
    public let output: FlexibleInt?
    public let cacheRead: FlexibleInt?
    public let cacheWrite: FlexibleInt?
    public let cacheWrite1h: FlexibleInt?
    public let reasoning: FlexibleInt?
    public let effort: String?
    public let tierAsked: String?
    public let tierSent: String?
    public let tierServed: String?
    public let millis: FlexibleInt?
    public let ttft: FlexibleInt?
    public let firstText: FlexibleInt?
    public let compaction: Bool?
    public let firstReasoning: FlexibleInt?
    public let reasoningHidden: Bool?
    public let sent: FlexibleInt?
    public let own: FlexibleInt?
    public let retried: FlexibleInt?
    public let queued: FlexibleInt?
    public let flow: FlexibleInt?
    public let status: FlexibleInt?
    public let error: String?
    public let errorType: String?
    public let requestID: String?
    public let responseID: String?
    public let endpoint: String?
    public let stop: String?
    public let session: String?
    public let nativeSession: String?
    public let subagent: String?
    public let parentAgent: String?
    public let rejected: Bool?
    public let tries: FlexibleInt?
    public let handedOn: Bool?
    public let kind: String?
    public let via: String?
    public let archive: String?
    public let computer: String?
    public let credits: FlexibleDouble?
    public let sessionRole: String?
    public let cost: FlexibleDouble?
    public let priced: Bool?
    public let swapped: Bool?
    public let routed: Bool?
    public let source: String?
    public let client: String?

    enum CodingKeys: String, CodingKey {
        case operation, agent, provider, host, model, served, upstream, effort, status, stop
        case compaction, subagent, rejected, tries, session
        case error = "err"
        case kind, via, archive, computer, credits, priced, swapped, routed, source, client, cost, reasoning
        case routeID = "route_id"
        case time = "t"
        case providerKeyID = "providerKeyId"
        case providerKeyName = "providerKeyName"
        case providerAccount = "providerAccount"
        case callerKeyID = "callerKeyId"
        case callerKeyName = "callerKeyName"
        case sessionProvider = "session_provider"
        case sessionAccount = "session_account"
        case sessionOfficialLogin = "session_official_login"
        case requested = "req"
        case input = "in"
        case output = "out"
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case cacheWrite1h = "cache_write_1h"
        case tierAsked = "tier_asked"
        case tierSent = "tier_sent"
        case tierServed = "tier_served"
        case millis = "ms"
        case ttft = "ttft_ms"
        case firstText = "first_text_ms"
        case firstReasoning = "first_reasoning_ms"
        case reasoningHidden = "reasoning_hidden"
        case sent = "sent_ms"
        case own = "own_ms"
        case retried = "retried_ms"
        case queued = "queued_ms"
        case flow = "flow_ms"
        case errorType = "err_type"
        case requestID = "rid"
        case responseID = "response_id"
        case endpoint = "ep"
        case nativeSession = "native_session"
        case parentAgent = "parent_agent"
        case handedOn = "handed_on"
        case sessionRole = "session_role"
    }
}
