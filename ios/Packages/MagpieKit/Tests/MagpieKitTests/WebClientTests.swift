import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MagpieKit

private actor KeyReads {
    var count = 0
    func read() -> String? { count += 1; return "demo-refreshed" }
}

final class WebClientTests: XCTestCase {
    private let base = URL(string: "https://example.ts.net")!
    private let hello = Data(#"{"name":"magpie","version":"demo"}"#.utf8)

    func testCookieRotationAndRequests() async throws {
        let transport = MockTransport(responses: [
            .init(data: hello, headers: ["Set-Cookie": "magpie_web_3430=demo-rotated; Path=/; HttpOnly; SameSite=Lax"]),
            .init(data: Data(#"{"seq":2,"routes":[]}"#.utf8)),
            .init(data: Data(#"{"seq":2,"routes":[]}"#.utf8)),
            .init(data: Data(#"{"days":[],"routes":[],"cut":false}"#.utf8))
        ])
        let client = WebClient(baseURL: base, runtimeKey: "demo-initial", transport: transport, port: 3430)
        let initial = await client.authState
        XCTAssertEqual(initial, .idle)
        _ = try await client.hello()
        _ = try await client.trace(after: 2, wait: true)
        _ = try await client.trace(after: 2, wait: false)
        _ = try await client.history(day: "2026-01-01")
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.timeoutInterval), [15, 35, 15, 15])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Cookie"), "magpie_web_3430=demo-initial")
        for request in requests.dropFirst() {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "magpie_web_3430=demo-rotated")
            XCTAssertFalse(request.httpShouldHandleCookies)
        }
        XCTAssertEqual(requests[1].url?.query, "after=2&wait=1")
        XCTAssertEqual(requests[2].url?.query, "after=2")
        XCTAssertEqual(requests[3].url?.query, "day=2026-01-01")
        let state = await client.authState
        XCTAssertEqual(state, .authenticated)
    }

    func testReauthenticationOnce() async throws {
        for status in [401, 403] {
            let reads = KeyReads()
            let transport = MockTransport(responses: [.init(status: status), .init(data: hello)])
            let client = WebClient(baseURL: base, runtimeKey: nil, transport: transport, port: 4000,
                                   keyProvider: { await reads.read() })
            _ = try await client.hello()
            let count = await reads.count
            let requests = await transport.requests
            let state = await client.authState
            XCTAssertEqual(count, 1)
            XCTAssertEqual(requests.count, 2)
            XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Cookie"), "magpie_web_4000=demo-refreshed")
            XCTAssertEqual(state, .authenticated)
        }
    }

    func testRepeatedUnauthorizedFails() async {
        let reads = KeyReads()
        let transport = MockTransport(responses: [.init(status: 401), .init(status: 403)])
        let client = WebClient(baseURL: base, runtimeKey: "demo", transport: transport, port: 3430,
                               keyProvider: { await reads.read() })
        do { _ = try await client.hello(); XCTFail() }
        catch { XCTAssertEqual(error as? MagpieError, .unauthorized) }
        let count = await reads.count
        let state = await client.authState
        let requests = await transport.requests
        XCTAssertEqual(count, 1)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(state, .failed)
        XCTAssertTrue(MagpieError.unauthorized.localizedChinese.contains("magpie 重启"))
        XCTAssertTrue(MagpieError.unauthorized.localizedChinese.contains("MAGPIE_WEB_KEY"))
    }
    func testReadOnlyWebEndpoints() async throws {
        let transport = try MockTransport.webFixtures()
        let client = WebClient(baseURL: base, runtimeKey: nil, transport: transport, port: 3430)
        let groups = try await client.groups()
        let providers = try await client.providers()
        let usage = try await client.usage(period: "7d")
        let quotas = try await client.usageQuotas()
        let route = try await client.route(id: 10038, day: "2026-10-17")
        XCTAssertEqual(groups.groups?.elements.count, 1)
        XCTAssertEqual(providers.providers?.elements.count, 1)
        XCTAssertEqual(usage.totals?.calls?.value, 30)
        XCTAssertEqual(quotas.elements.count, 4)
        XCTAssertEqual(route.id?.value, 10038)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.httpMethod }, Array(repeating: "GET", count: 5))
        XCTAssertEqual(requests[2].url?.query, "period=7d")
        XCTAssertNil(requests[3].url?.query)
        XCTAssertEqual(requests[4].url?.query, "day=2026-10-17&id=10038")
    }

    func testMockTraceNewestRouteIsRebasedNearNow() async throws {
        let raw = try MagpieJSON.decoder.decode(TraceEnvelope.self, from: MockFixtures.data(named: "trace"))
        let rawRoute = try XCTUnwrap(RoutingModel.currentRoute(in: raw.routes?.elements ?? []))
        let rawStart = try XCTUnwrap(rawRoute.time?.date)
        let rawTryStart = try XCTUnwrap(rawRoute.tries?.elements.first?.start?.date)
        let client = WebClient(baseURL: base, runtimeKey: nil, transport: try MockTransport.webFixtures(), port: 3430)
        let trace = try await client.trace(after: 0, wait: false)
        try assertTraceRebased(trace, rawStart: rawStart, rawTryStart: rawTryStart)
    }

    func testDirectTraceFixtureIsRebasedOnInit() async throws {
        let rawData = try MockFixtures.data(named: "trace")
        let raw = try MagpieJSON.decoder.decode(TraceEnvelope.self, from: rawData)
        let rawRoute = try XCTUnwrap(RoutingModel.currentRoute(in: raw.routes?.elements ?? []))
        let transport = MockTransport(fixtures: ["/api/gateway/trace": rawData])
        let url = try XCTUnwrap(URL(string: "https://example.ts.net/api/gateway/trace"))
        let (data, response) = try await transport.send(URLRequest(url: url))
        XCTAssertEqual(response.statusCode, 200)
        let trace = try MagpieJSON.decoder.decode(TraceEnvelope.self, from: data)
        try assertTraceRebased(trace, rawStart: try XCTUnwrap(rawRoute.time?.date), rawTryStart: try XCTUnwrap(rawRoute.tries?.elements.first?.start?.date))
    }

    private func assertTraceRebased(_ trace: TraceEnvelope, rawStart: Date, rawTryStart: Date) throws {
        let route = try XCTUnwrap(RoutingModel.currentRoute(in: trace.routes?.elements ?? []))
        let start = try XCTUnwrap(route.time?.date)
        let tryStart = try XCTUnwrap(route.tries?.elements.first?.start?.date)
        let now = try XCTUnwrap(trace.now?.date)
        let shift = start.timeIntervalSince(rawStart)
        XCTAssertEqual(start.timeIntervalSinceNow, -8, accuracy: 2)
        XCTAssertEqual(shift, Date().timeIntervalSince(rawStart) - 8, accuracy: 2)
        XCTAssertEqual(tryStart.timeIntervalSince(rawTryStart), shift, accuracy: 0.05)
        XCTAssertEqual(now.timeIntervalSince(start), 8, accuracy: 2)
        XCTAssertEqual(route.tries?.elements.first?.done, false)
    }

}
