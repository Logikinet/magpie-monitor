import XCTest
@testable import MagpieKit

final class ModelTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        return try MagpieJSON.decoder.decode(T.self, from: MockFixtures.data(named: name))
    }

    func testFixturesDecode() throws {
        XCTAssertEqual(try fixture("hello", as: GatewayHello.self).name, "magpie")
        let url = Bundle.module.url(forResource: "ledger_bad_rows", withExtension: "json", subdirectory: "Fixtures")!
        let ledger = try MagpieJSON.decoder.decode(Ledger.self, from: Data(contentsOf: url))
        XCTAssertEqual(ledger.rows.elements.count, 1)
        XCTAssertEqual(ledger.rows.badCount, 2)
        XCTAssertEqual(ledger.rows.elements.first?.input?.value, 12)
        XCTAssertEqual(ledger.rows.elements.first?.sessionRole, "root")
        XCTAssertEqual(try fixture("quotas", as: QuotaList.self).data.elements.first?.weeklyWindow?.remaining?.value, 75)
        let cards = try fixture("quota_cards", as: QuotaCardList.self)
        XCTAssertEqual(cards.data.elements.first?.accessSKU, "demo-plan")
        XCTAssertEqual(cards.data.elements.first?.windows?.elements.first?.limit?.value, 100)
        XCTAssertEqual(try fixture("concurrency", as: Concurrency.self).data?["anthropic#fake"]?.busy?.value, 2)
        XCTAssertEqual(try fixture("trace", as: TraceEnvelope.self).routes?.elements.count, 1)
        XCTAssertEqual(try fixture("usage", as: UsageSummary.self).totals?.calls?.value, 3)
        XCTAssertEqual(try fixture("route", as: RouteLookup.self).route?.id?.value, 41)
    }

    func testDatesAndMissingOptionals() throws {
        let decoder = MagpieJSON.decoder
        let fractional = try decoder.decode(MagpieDate.self, from: Data("\"2026-10-17T08:30:00.125Z\"".utf8))
        let whole = try decoder.decode(MagpieDate.self, from: Data("\"2026-10-17T08:30:00Z\"".utf8))
        XCTAssertNotNil(fractional.date); XCTAssertEqual(fractional.rawString, "2026-10-17T08:30:00.125Z"); XCTAssertNotNil(whole.date)
        let numeric = try decoder.decode(MagpieDate.self, from: Data("1792225800000".utf8))
        XCTAssertNotNil(numeric.date)
        let minimal = try decoder.decode(LedgerRow.self, from: Data("{\"agent\":\"claude-code\"}".utf8))
        XCTAssertNil(minimal.sessionRole); XCTAssertNil(minimal.time)
    }

    func testWindowLookupNormalizesNames() throws {
        let quota = try fixture("quotas", as: QuotaList.self).data.elements[0]
        XCTAssertEqual(quota.fiveHourWindow?.name, "5-hour")
        XCTAssertEqual(quota.weeklyWindow?.name, "Weekly")
    }
}
