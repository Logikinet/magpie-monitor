import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MagpieKit

final class NetworkingTests: XCTestCase {
    private let baseURL = URL(string: "https://example.ts.net")!

    func testRoutingAndOverrides() async throws {
        let transport = MockTransport(fixtures: ["/a": Data("base".utf8), "/a?x=1": Data("query".utf8)],
                                      statuses: ["/a?x=2": 403])
        for (path, text, status) in [("/a", "base", 200), ("/a?x=1", "query", 200),
                                     ("/a?x=2", "base", 403), ("/unknown", "", 404)] {
            let (data, response) = try await transport.send(URLRequest(url: URL(string: path, relativeTo: baseURL)!))
            XCTAssertEqual(String(decoding: data, as: UTF8.self), text)
            XCTAssertEqual(response.statusCode, status)
        }
        let failing = MockTransport(fixtures: [:], errors: ["/a": .timeout])
        do { _ = try await failing.send(URLRequest(url: baseURL.appendingPathComponent("a"))); XCTFail() }
        catch { XCTAssertEqual(error as? MagpieError, .timeout) }
    }

    func testDirectoryAndCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("api"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try MockFixtures.data(named: "hello").write(to: directory.appendingPathComponent("api/hello.json"))
        let transport = try MockTransport(directoryURL: directory)
        let (data, response) = try await transport.send(URLRequest(url: baseURL.appendingPathComponent("api/hello")))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(try MagpieJSON.decoder.decode(GatewayHello.self, from: data).name, "magpie")
        let task = Task {
            try await MockTransport(fixtures: [:], delay: 60).send(URLRequest(url: baseURL))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail() }
        catch { XCTAssertEqual(MagpieError.map(error), .cancelled) }
    }

    func testClassificationAndRedaction() throws {
        for code in [200, 201, 204, 299] { XCTAssertNil(MagpieError.classify(status: code)) }
        XCTAssertEqual(MagpieError.classify(status: 401), .unauthorized)
        XCTAssertEqual(MagpieError.classify(status: 403), .forbidden)
        XCTAssertEqual(MagpieError.classify(status: 500), .badStatus(500))
        XCTAssertEqual(MagpieError.map(URLError(.timedOut)), .timeout)
        XCTAssertEqual(MagpieError.map(URLError(.cancelled)), .cancelled)
        if case .network = MagpieError.map(URLError(.notConnectedToInternet)) {} else { XCTFail() }
        XCTAssertEqual(Redactor.redact(""), "••••")
        XCTAssertEqual(Redactor.redact("a"), "••••a")
        XCTAssertEqual(Redactor.redact("abcd"), "••••cd")
        var request = URLRequest(url: URL(string: "https://example.ts.net/a?key=demo-value&x=1&%6bey=other-value")!)
        request.setValue("Bearer demo-header", forHTTPHeaderField: "Authorization")
        request.setValue("demo-cookie", forHTTPHeaderField: "Cookie")
        let description = Redactor.requestDescription(request)
        for secret in ["demo-value", "other-value", "demo-header", "demo-cookie", "Authorization", "Cookie"] {
            XCTAssertFalse(description.contains(secret))
        }
        XCTAssertTrue(description.contains("x=1"))
    }

    func testRequestConstruction() throws {
        for base in ["https://example.ts.net/prefix", "https://example.ts.net/prefix/"] {
            let client = GatewayClient(baseURL: URL(string: base)!, key: "demo", transport: MockTransport(fixtures: [:]), timeout: 7)
            let request = try client.makeRequest(path: "/api/hello", query: ["z": "a&b", "a": "会话"])
            XCTAssertEqual(request.url?.path, "/prefix/api/hello")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.map(\.name), ["a", "z"])
            XCTAssertEqual(query?.last?.value, "a&b")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer demo")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.timeoutInterval, 7)
        }
        for key in [nil, ""] as [String?] {
            let client = GatewayClient(baseURL: baseURL, key: key, transport: MockTransport(fixtures: [:]))
            XCTAssertNil(try client.makeRequest(path: "api/hello").value(forHTTPHeaderField: "Authorization"))
        }
    }

    func testGatewayFixtures() async throws {
        let mapping = ["/api/hello": "hello", "/v1/magpie/usage?period=day": "usage",
                       "/v1/magpie/usage/requests?agent=demo&limit=5&offset=2&period=day": "ledger",
                       "/v1/magpie/quotas?kept=1": "quotas", "/v1/magpie/quotas/cards": "quota_cards",
                       "/v1/magpie/route?after=1&session=demo&wait=2": "route", "/v1/magpie/concurrency": "concurrency"]
        var fixtures = try mapping.mapValues { try MockFixtures.data(named: $0) }
        fixtures["/v1/magpie/limit"] = Data(#"{"enabled":true,"amount":3,"extra":[null,"ok",{}]}"#.utf8)
        let client = GatewayClient(baseURL: baseURL, key: nil, transport: MockTransport(fixtures: fixtures))
        let hello = try await client.hello()
        XCTAssertEqual(hello.name, "magpie")
        let usage = try await client.usage(period: "day")
        XCTAssertEqual(usage.totals?.calls?.value, 30)
        let ledger = try await client.requests(period: "day", offset: 2, limit: 5, filters: ["agent": "demo"])
        XCTAssertEqual(ledger.rows.elements.count, 30)
        let quotas = try await client.quotas(kept: true)
        XCTAssertFalse(quotas.data.elements.isEmpty)
        let cards = try await client.quotaCards()
        XCTAssertFalse(cards.data.elements.isEmpty)
        let route = try await client.route(session: "demo", after: 1, wait: 2)
        XCTAssertEqual(route.route?.id?.value, 4129)
        let concurrency = try await client.concurrency()
        XCTAssertEqual(concurrency.data?["anthropic#key-demo-1"]?.busy?.value, 2)
        let limit = try await client.limit()
        XCTAssertEqual(limit["enabled"], .bool(true))
    }

    func testGatewayErrors() async throws {
        for (status, expected) in [(401, MagpieError.unauthorized), (403, .forbidden), (503, .badStatus(503))] {
            let client = GatewayClient(baseURL: baseURL, key: nil,
                                       transport: MockTransport(fixtures: [:], statuses: ["/api/hello": status]))
            do { _ = try await client.hello(); XCTFail() }
            catch { XCTAssertEqual(error as? MagpieError, expected) }
        }
        let client = GatewayClient(baseURL: baseURL, key: nil,
                                   transport: MockTransport(fixtures: ["/api/hello": Data("bad".utf8)]))
        do { _ = try await client.hello(); XCTFail() }
        catch { guard case .decoding = error as? MagpieError else { return XCTFail() } }
    }
}
