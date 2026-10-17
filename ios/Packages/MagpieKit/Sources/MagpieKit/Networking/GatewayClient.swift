import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GatewayClient: Sendable {
    private let baseURL: URL
    private let key: String?
    private let transport: any HTTPTransport
    private let timeout: TimeInterval

    public init(baseURL: URL, key: String?, transport: any HTTPTransport, timeout: TimeInterval = 15) {
        self.baseURL = baseURL
        self.key = key
        self.transport = transport
        self.timeout = timeout
    }

    public func makeRequest(path: String, query: [String: String] = [:]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty else { throw URLError(.badURL) }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/").map(String.init).joined(separator: "/")
        components.path = "/" + ([components.path, path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
            .filter { !$0.isEmpty }.joined(separator: "/"))
        components.queryItems = query.isEmpty ? nil : query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        components.fragment = nil
        components.user = nil
        components.password = nil
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key, !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        return request
    }

    public func hello() async throws -> GatewayHello { try await get("/api/hello") }
    public func usage(period: String) async throws -> UsageSummary {
        try await get("/v1/magpie/usage", query: ["period": period])
    }
    public func requests(period: String, offset: Int = 0, limit: Int = 50,
                         filters: [String: String] = [:]) async throws -> Ledger {
        var query = filters
        query["period"] = period
        query["offset"] = String(offset)
        query["limit"] = String(limit)
        return try await get("/v1/magpie/usage/requests", query: query)
    }
    public func quotas(kept: Bool = false) async throws -> QuotaList {
        try await get("/v1/magpie/quotas", query: kept ? ["kept": "1"] : [:])
    }
    public func quotaCards() async throws -> QuotaCardList { try await get("/v1/magpie/quotas/cards") }
    public func route(session: String, after: Int? = nil, wait: Int? = nil) async throws -> RouteLookup {
        var query = ["session": session]
        if let after { query["after"] = String(after) }
        if let wait { query["wait"] = String(wait) }
        return try await get("/v1/magpie/route", query: query)
    }
    public func concurrency() async throws -> Concurrency { try await get("/v1/magpie/concurrency") }
    public func limit() async throws -> [String: JSONValue] { try await get("/v1/magpie/limit") }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        do {
            let (data, response) = try await transport.send(makeRequest(path: path, query: query))
            try Task.checkCancellation()
            if let error = MagpieError.classify(status: response.statusCode) { throw error }
            do { return try MagpieJSON.decoder.decode(T.self, from: data) }
            catch { throw MagpieError.decoding("服务器响应格式不正确") }
        } catch { throw MagpieError.map(error) }
    }
}
