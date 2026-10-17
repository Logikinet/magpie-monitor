import Foundation

public struct TraceEnvelope: Decodable, Sendable {
    public let seq: FlexibleInt?
    public let routes: LossyArray<Route>?
    public let totals: TraceTotals?
    public let mine: Bool?
    public let now: MagpieDate?
}

public struct TraceTotals: Decodable, Sendable {
    public let requests: FlexibleInt?
    public let rerouted: FlexibleInt?
    public let errors: FlexibleInt?
}

public struct Route: Decodable, Sendable {
    public let seq: FlexibleInt?
    public let id: FlexibleInt?
    public let time: MagpieDate?
    public let agent: String?
    public let parentSession: String?
    public let session: String?
    public let usage: LossyArray<RouteUsage>?
    public let kind: String?
    public let model: String?
    public let effort: String?
    public let tier: String?
    public let provider: String?
    public let group: RouteGroup?
    public let rule: RouteRule?
    public let leadAccount: String?
    public let subagent: RouteSubagent?
    public let pinned: String?
    public let order: LossyArray<Weighed>?
    public let done: Bool?
    public let status: FlexibleInt?
    public let error: String?
    public let priced: Bool?
}

public struct RouteUsage: Decodable, Sendable {
    public let provider: String?
    public let model: String?
    public let input: FlexibleInt?
    public let output: FlexibleInt?
    public let cacheRead: FlexibleInt?
    public let cacheWrite: FlexibleInt?
    public let reasoning: FlexibleInt?

    enum CodingKeys: String, CodingKey {
        case provider, model, reasoning
        case input = "in"
        case output = "out"
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }
}

public struct Weighed: Decodable, Sendable {
    public let id: String?
    public let provider: String?
    public let name: String?
    public let icon: String?
    public let preset: String?
    public let who: String?
    public let kind: String?
    public let agent: String?
    public let plan: String?
    public let model: String?
    public let fixed: String?
    public let fast: Bool?
    public let routing: String?
    public let fallback: Bool?
    public let shared: Bool?
    public let used: FlexibleDouble?
    public let amount: FlexibleDouble?
    public let limit: FlexibleDouble?
    public let unit: String?
    public let pace: FlexibleDouble?
    public let tokens: FlexibleDouble?
    public let rank: FlexibleInt?
    public let turn: Bool?
}

public struct RouteGroup: Decodable, Sendable {
    public let id: String?
    public let name: String?
    public let routing: String?
    public let affinity: String?
    public let members: [String]?
}

public struct RouteRule: Decodable, Sendable {
    public let name: String?
    public let reason: String?
}

public struct RouteSubagent: Decodable, Sendable {
    public let name: String?
    public let model: String?
    public let effort: String?
}

public struct RouteLookup: Decodable, Sendable {
    public let session: String?
    public let seq: FlexibleInt?
    public let route: Route?
}

public struct HistoryEnvelope: Decodable, Sendable {
    public let days: LossyArray<HistoryDay>?
    public let routes: LossyArray<Route>?
    public let cut: Bool?
}

public struct HistoryDay: Decodable, Sendable {
    public let day: String?
    public let requests: FlexibleInt?
}
