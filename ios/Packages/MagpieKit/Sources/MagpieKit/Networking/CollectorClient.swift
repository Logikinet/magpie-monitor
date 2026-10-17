import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CollectorClient: Sendable {
    private let baseURL: URL
    private let key: String?
    private let transport: any HTTPTransport
    /// Base URL is the collector origin (optionally behind a path prefix).
    public init(baseURL: URL, key: String?, transport: any HTTPTransport) {
        self.baseURL = baseURL; self.key = key; self.transport = transport
    }
    public func makeRequest(path: String, query: [String: String] = [:]) throws -> URLRequest {
        var request = try GatewayClient(baseURL: baseURL, key: nil, transport: transport)
            .makeRequest(path: "v1/collector/" + path, query: query)
        if let key, !key.isEmpty { request.setValue(key, forHTTPHeaderField: "X-Collector-Key") }
        return request
    }
    public func hello() async throws -> CollectorRecord { try await get("hello") }
    public func sys() async throws -> CollectorRecord { try await get("sys") }
    public func services(scope: String = "all") async throws -> CollectorRecord {
        try await get("services", query: ["scope": scope])
    }
    public func chart(n: Int = 24) async throws -> [CollectorRecord] {
        try await get("chart", query: ["n": String(min(24, max(1, n)))])
    }
    public func tmux() async throws -> CollectorRecord { try await get("tmux") }
    public func capture(target: String, lines: Int = 300, ansi: Bool = true) async throws -> CollectorRecord {
        try await get("tmux/capture", query: ["target": target, "lines": String(min(2000, max(20, lines))), "ansi": ansi ? "1" : "0"])
    }
    public func runtimes() async throws -> CollectorRecord { try await get("runtimes") }
    public func runtime(id: String) async throws -> CollectorRecord {
        guard !id.isEmpty, id.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) else { throw URLError(.badURL) }
        return try await get("runtimes/" + id)
    }
    public func tasks() async throws -> CollectorRecord { try await get("tasks") }
    public func activity(limit: Int = 200) async throws -> CollectorRecord {
        try await get("activity", query: ["limit": String(min(200, max(1, limit)))])
    }
    public func repos() async throws -> CollectorRecord { try await get("repos") }
    public func tailscale() async throws -> CollectorRecord { try await get("tailscale") }
    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        do {
            let (data, response) = try await transport.send(makeRequest(path: path, query: query))
            try Task.checkCancellation()
            if let error = MagpieError.classify(status: response.statusCode) { throw error }
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch { throw MagpieError.decoding("服务器响应格式不正确") }
        } catch { throw MagpieError.map(error) }
    }
}
