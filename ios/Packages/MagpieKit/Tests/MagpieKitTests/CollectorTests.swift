import XCTest
import Foundation
@testable import MagpieKit

final class CollectorTests: XCTestCase {
    func testTolerantMetricsAndUnknownFields() throws {
        let record = try JSONDecoder().decode(CollectorRecord.self, from: Data(#"{"hostname":"devbox","cpu_usage":null,"mem":{"total":"8192"},"future":{"value":true},"services":null}"#.utf8))
        XCTAssertNil(record.number("cpu_usage"))
        XCTAssertNil(record.number("uptime"))
        XCTAssertEqual(record.object("mem")?.number("total"), 8192)
        XCTAssertEqual(record.object("future")?.flag("value"), true)
        XCTAssertTrue(record.records("services").isEmpty)
    }

    func testAllOfflineEndpointsAndAuthentication() async throws {
        let transport = try MockTransport.collectorFixtures()
        let client = CollectorClient(baseURL: URL(string: "https://example.ts.net")!, key: "demo-key", transport: transport)
        let hello = try await client.hello()
        XCTAssertEqual(hello.string("host"), "devbox")
        let sys = try await client.sys()
        XCTAssertEqual(sys.number("cpu_count"), 8)
        let services = try await client.services(scope: "user")
        XCTAssertEqual(services.records("services").count, 3)
        let chart = try await client.chart()
        XCTAssertEqual(chart.count, 24)
        XCTAssertLessThan(chart.first!.number("t")!, chart.last!.number("t")!)
        let tmux = try await client.tmux()
        XCTAssertEqual(tmux.records("sessions").first?.string("name"), "devbox")
        let capture = try await client.capture(target: "%1")
        XCTAssertEqual(capture.string("target"), "%1")
        _ = try await client.runtimes()
        _ = try await client.runtime(id: "codex")
        _ = try await client.tasks()
        _ = try await client.activity()
        _ = try await client.repos()
        _ = try await client.tailscale()
        _ = try await client.chart(n: 0)
        _ = try await client.capture(target: "%1", lines: 9000, ansi: false)
        _ = try await client.activity(limit: 9000)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 15)
        let boundedQueries = requests.suffix(3).compactMap { request in
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        }
        XCTAssertEqual(boundedQueries[0].first { $0.name == "n" }?.value, "1")
        XCTAssertEqual(boundedQueries[1].first { $0.name == "lines" }?.value, "2000")
        XCTAssertEqual(boundedQueries[1].first { $0.name == "ansi" }?.value, "0")
        XCTAssertEqual(boundedQueries[2].first { $0.name == "limit" }?.value, "200")
        for request in requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Collector-Key"), "demo-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        }
        let captureURL = try XCTUnwrap(requests.first { $0.url?.path.hasSuffix("capture") == true }?.url)
        let query = URLComponents(url: captureURL, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "target" }?.value, "%1")
        XCTAssertEqual(query.first { $0.name == "ansi" }?.value, "1")
    }

    func testErrorsBoundsAndProfileCompatibility() async throws {
        let transport = MockTransport(responses: [.init(status: 401), .init(data: Data("bad JSON".utf8))])
        let client = CollectorClient(baseURL: URL(string: "https://example.ts.net/prefix")!, key: nil, transport: transport)
        do { _ = try await client.sys(); XCTFail("Expected authentication error") }
        catch { XCTAssertEqual(error as? MagpieError, .unauthorized) }
        do { _ = try await client.sys(); XCTFail("Expected decoding error") }
        catch { guard case .decoding = error as? MagpieError else { return XCTFail("Wrong error") } }
        let request = try client.makeRequest(path: "sys")
        XCTAssertEqual(request.url?.path, "/prefix/v1/collector/sys")
        var profile = ProfileConfig(name: "devbox", gatewayURL: "https://example.ts.net")
        let data = try JSONEncoder().encode(profile)
        XCTAssertNil(try JSONDecoder().decode(ProfileConfig.self, from: data).collectorURL)
        profile.collectorURL = "http://devbox.example.ts.net:8080"
        XCTAssertTrue(profile.isInsecure)
        XCTAssertTrue(profile.validate().isEmpty)
        profile.collectorURL = "https://demo:key@example.ts.net"
        XCTAssertFalse(profile.validate().isEmpty)
        do { _ = try await client.runtime(id: "../sys"); XCTFail("Invalid runtime ID") } catch {}
    }
}
