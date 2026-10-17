import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MockTransport: HTTPTransport {
    public struct Response: Sendable {
        public let data: Data
        public let status: Int
        public let headers: [String: String]
        public let error: MagpieError?

        public init(data: Data = Data(), status: Int = 200,
                    headers: [String: String] = [:], error: MagpieError? = nil) {
            self.data = data
            self.status = status
            self.headers = headers
            self.error = error
        }
    }

    public private(set) var requests: [URLRequest] = []
    private var responses: [Response] = []

    /// Sanitized fixtures for the read-only Web GUI endpoints.
    public static func webFixtures() throws -> MockTransport {
        let resources = ["/api/hello": "hello", "/api/gateway/trace": "trace",
                         "/api/groups": "groups", "/api/providers": "providers",
                         "/api/usage": "usage", "/api/usage/quotas": "usage_quotas",
                         "/api/gateway/route": "web_route"]
        return MockTransport(fixtures: try resources.mapValues { try MockFixtures.data(named: $0) })
    }

    /// Scripted responses are consumed in order, then fixture routing resumes.
    public init(responses: [Response]) {
        self.responses = responses
        self.fixtures = [:]
        self.delay = 0
        self.errors = [:]
        self.statuses = [:]
    }

    private let fixtures: [String: Data]
    private let delay: TimeInterval
    private let errors: [String: MagpieError]
    private let statuses: [String: Int]

    public init(fixtures: [String: Data], delay: TimeInterval = 0,
                errors: [String: MagpieError] = [:], statuses: [String: Int] = [:]) {
        self.fixtures = fixtures
        self.delay = delay
        self.errors = errors
        self.statuses = statuses
    }

    /// Files mirror URL paths, e.g. api/hello.json -> /api/hello.
    public init(directoryURL: URL, delay: TimeInterval = 0,
                errors: [String: MagpieError] = [:], statuses: [String: Int] = [:]) throws {
        var fixtures: [String: Data] = [:]
        guard let files = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw MagpieError.network("无法读取模拟数据目录")
        }
        for case let file as URL in files where file.pathExtension == "json" {
            let relative = String(file.path.dropFirst(directoryURL.standardizedFileURL.path.count)).dropFirst()
            fixtures["/" + String(relative.dropLast(5))] = try Data(contentsOf: file)
        }
        self.init(fixtures: fixtures, delay: delay, errors: errors, statuses: statuses)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        requests.append(request)
        if delay > 0, delay.isFinite {
            try await Task.sleep(for: .seconds(delay))
        }
        try Task.checkCancellation()
        guard let url = request.url else { throw URLError(.badURL) }
        if !responses.isEmpty {
            let next = responses.removeFirst()
            if let error = next.error { throw error }
            guard let response = HTTPURLResponse(url: url, statusCode: next.status, httpVersion: "HTTP/1.1",
                                                 headerFields: next.headers) else {
                throw MagpieError.network("无法创建模拟响应")
            }
            return (next.data, response)
        }
        let path = url.path
        let exact = path + (url.query.map { "?" + $0 } ?? "")
        if let error = errors[exact] ?? errors[path] { throw error }
        let data = fixtures[exact] ?? fixtures[path]
        let status = statuses[exact] ?? statuses[path] ?? (data == nil ? 404 : 200)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else {
            throw MagpieError.network("无法创建模拟响应")
        }
        return (data ?? Data(), response)
    }
}
