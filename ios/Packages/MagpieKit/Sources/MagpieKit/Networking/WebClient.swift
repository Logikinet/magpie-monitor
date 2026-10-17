import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AuthState: Sendable, Equatable {
    case idle, authenticated, failed
}

public actor WebClient: TraceSource {
    public private(set) var authState: AuthState = .idle
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let cookieName: String
    private var key: String?
    private let keyProvider: @Sendable () async -> String?

    public init(baseURL: URL, runtimeKey: String?, transport: any HTTPTransport, port: Int,
                keyProvider: (@Sendable () async -> String?)? = nil) {
        self.baseURL = baseURL
        self.key = runtimeKey
        self.transport = transport
        self.cookieName = "magpie_web_\(port)"
        self.keyProvider = keyProvider ?? { runtimeKey }
    }

    public func hello() async throws -> GatewayHello { try await get("/api/hello") }

    public func trace(after: Int, wait: Bool) async throws -> TraceEnvelope {
        var query = ["after": String(after)]
        if wait { query["wait"] = "1" }
        return try await get("/api/gateway/trace", query: query, timeout: wait ? 35 : 15)
    }

    public func history(day: String) async throws -> HistoryEnvelope {
        try await get("/api/gateway/history", query: ["day": day])
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:],
                                   timeout: TimeInterval = 15) async throws -> T {
        do {
            for attempt in 0...1 {
                // Reuse the common URL builder without injecting gateway credentials.
                var request = try GatewayClient(baseURL: baseURL, key: nil, transport: transport,
                                                timeout: timeout).makeRequest(path: path, query: query)
                request.httpShouldHandleCookies = false
                if let key, !key.isEmpty { request.setValue("\(cookieName)=\(key)", forHTTPHeaderField: "Cookie") }
                let (data, response) = try await transport.send(request)
                try Task.checkCancellation()
                var headers: [String: String] = [:]
                for (name, value) in response.allHeaderFields {
                    headers[String(describing: name)] = String(describing: value)
                }
                if let url = response.url,
                   let cookie = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
                    .first(where: { $0.name == cookieName }) {
                    key = cookie.value
                }
                if response.statusCode == 401 || response.statusCode == 403 {
                    if attempt == 0 {
                        key = await keyProvider()
                        try Task.checkCancellation()
                        continue
                    }
                    authState = .failed
                    throw MagpieError.unauthorized
                }
                if let error = MagpieError.classify(status: response.statusCode) { throw error }
                authState = .authenticated
                do { return try MagpieJSON.decoder.decode(T.self, from: data) }
                catch { throw MagpieError.decoding("服务器响应格式不正确") }
            }
            throw MagpieError.unauthorized
        } catch { throw MagpieError.map(error) }
    }
}
