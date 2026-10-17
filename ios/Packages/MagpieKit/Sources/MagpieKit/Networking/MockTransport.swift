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
        let fixtures = try resources.mapValues { try MockFixtures.data(named: $0) }
        return MockTransport(fixtures: fixtures)
    }

    public static func collectorFixtures() throws -> MockTransport {
        let routes = ["hello", "sys", "services", "chart", "tmux", "runtimes", "tasks", "activity", "repos", "tailscale"]
        var fixtures: [String: Data] = [:]
        for route in routes { fixtures["/v1/collector/" + route] = try MockFixtures.data(named: "collector_" + route) }
        fixtures["/v1/collector/tmux/capture"] = try MockFixtures.data(named: "collector_capture")
        fixtures["/v1/collector/runtimes/codex"] = try MockFixtures.data(named: "collector_runtime")
        return MockTransport(fixtures: fixtures)
    }

    private static func rebaseTrace(_ data: Data, now: Date) throws -> Data {
        // Anchor the newest route a few seconds in the past. Fixture clocks are absolute,
        // so an unshifted start lands in the future and elapsed time clamps to 0.
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        func sequence(_ route: [String: Any]) -> Int {
            return (route["seq"] as? NSNumber)?.intValue ?? 0
        }
        func parseDate(_ text: String) -> Date? {
            return formatter.date(from: text) ?? plainFormatter.date(from: text)
        }
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = root["routes"] as? [[String: Any]],
              let latest = routes.max(by: { sequence($0) < sequence($1) }),
              let routeTime = latest["time"] as? String,
              let fixtureStart = parseDate(routeTime) else { return data }
        let offset = now.addingTimeInterval(-8).timeIntervalSince(fixtureStart)
        func shiftDates(_ value: Any, key: String? = nil) -> Any {
            if let array = value as? [Any] { return array.map { shiftDates($0, key: key) } }
            if let object = value as? [String: Any] {
                return Dictionary(uniqueKeysWithValues: object.map { name, child in
                    (name, shiftDates(child, key: name))
                })
            }
            // `done` on a try is a Bool. Only ISO-8601 strings are moved.
            if let key, ["time", "start", "done", "now", "until", "due", "renews", "usedRenews"].contains(key),
               let text = value as? String, let date = parseDate(text) {
                return formatter.string(from: date.addingTimeInterval(offset))
            }
            return value
        }
        root = shiftDates(root) as? [String: Any] ?? root
        root["now"] = formatter.string(from: now)
        return try JSONSerialization.data(withJSONObject: root)
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
        var prepared = fixtures
        if let trace = prepared["/api/gateway/trace"], let shifted = try? Self.rebaseTrace(trace, now: Date()) {
            prepared["/api/gateway/trace"] = shifted
        }
        self.fixtures = prepared
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
