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
        XCTAssertEqual(try fixture("quotas", as: QuotaList.self).data.elements.count, 4)
        let cards = try fixture("quota_cards", as: QuotaCardList.self)
        XCTAssertEqual(cards.data.elements.first?.accessSKU, "demo-plan-1")
        XCTAssertEqual(cards.data.elements.first?.windows?.elements.first?.limit?.value, 100)
        XCTAssertEqual(try fixture("concurrency", as: Concurrency.self).data?["anthropic#key-demo-1"]?.busy?.value, 2)
        XCTAssertEqual(try fixture("trace", as: TraceEnvelope.self).routes?.elements.count, 40)
        XCTAssertEqual(try fixture("usage", as: UsageSummary.self).totals?.calls?.value, 30)
        XCTAssertEqual(try fixture("route", as: RouteLookup.self).route?.id?.value, 4129)
    }

    func testEveryMockJSONDecodesWithoutBadRows() throws {
        let ledger = try fixture("ledger", as: Ledger.self)
        XCTAssertEqual(ledger.rows.elements.count, 30)
        XCTAssertEqual(ledger.rows.badCount, 0)
        XCTAssertEqual(ledger.series?.elements.count, 24)
        XCTAssertEqual(ledger.series?.badCount, 0)
        let quotas = try fixture("quotas", as: QuotaList.self)
        XCTAssertEqual(quotas.data.badCount, 0)
        XCTAssertTrue(quotas.data.elements.allSatisfy { $0.windows?.badCount == 0 })
        let cards = try fixture("quota_cards", as: QuotaCardList.self)
        XCTAssertEqual(cards.data.badCount, 0)
        XCTAssertTrue(cards.data.elements.allSatisfy { $0.windows?.badCount == 0 })
        let trace = try fixture("trace", as: TraceEnvelope.self)
        XCTAssertEqual(trace.routes?.elements.count, 40)
        XCTAssertEqual(trace.routes?.badCount, 0)
        XCTAssertTrue(trace.routes?.elements.allSatisfy { $0.usage?.badCount == 0 && $0.order?.badCount == 0 } == true)
        _ = try fixture("hello", as: GatewayHello.self)
        _ = try fixture("usage", as: UsageSummary.self)
        _ = try fixture("concurrency", as: Concurrency.self)
        _ = try fixture("route", as: RouteLookup.self)
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

    func testQuotaPercentagesPreferReportedUsageOverAmount() throws {
        let quotas = try fixture("quotas", as: QuotaList.self)
        let percentages = quotas.data.elements.flatMap { quota in
            quota.windows?.elements.compactMap(\.usedPercentage) ?? []
        }
        XCTAssertEqual(percentages, [48, 52, 73, 27, 94, 6, 29, 71])
    }

    func testQuotaPercentageFallbacksAndBounds() throws {
        func percentage(_ fields: String) throws -> Double? {
            let data = Data(("{\"name\":\"5-hour\"," + fields + "}").utf8)
            return try MagpieJSON.decoder.decode(QuotaSpan.self, from: data).usedPercentage
        }
        XCTAssertEqual(try percentage(#""remaining": 65, "amount": 100, "limit": 100"#), 35)
        XCTAssertEqual(try percentage(#""amount": 40, "limit": 200"#), 20)
        XCTAssertEqual(try percentage(#""used": 0, "remaining": 20"#), 0)
        XCTAssertEqual(try percentage(#""used": 125"#), 100)
        XCTAssertEqual(try percentage(#""used": -5"#), 0)
        XCTAssertNil(try percentage(#""amount": 10, "limit": 0"#))
        XCTAssertNil(try percentage(#""used": 25, "unlimited": true"#))
        XCTAssertNil(try percentage(#""limit": 100"#))
    }

    func testWindowLookupNormalizesNames() throws {
        let url = Bundle.module.url(forResource: "quota_windows", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let quota = try MagpieJSON.decoder.decode(QuotaList.self, from: data).data.elements[0]
        XCTAssertEqual(quota.fiveHourWindow?.name, "5-hour")
        XCTAssertEqual(quota.weeklyWindow?.name, "Weekly")
    }

    func testTokenFormatterLocalesAndBoundaries() {
        let zh = Locale(identifier: "zh_CN")
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(TokenFormatter.compact(0, locale: zh), "0")
        XCTAssertEqual(TokenFormatter.compact(9_999, locale: zh), "9,999")
        XCTAssertEqual(TokenFormatter.compact(10_000, locale: zh), "1 万")
        XCTAssertEqual(TokenFormatter.compact(1_284_000, locale: zh), "128.4 万")
        XCTAssertEqual(TokenFormatter.compact(100_000_000, locale: zh), "1 亿")
        XCTAssertEqual(TokenFormatter.compact(0, locale: en), "0")
        XCTAssertEqual(TokenFormatter.compact(9_999, locale: en), "9,999")
        XCTAssertEqual(TokenFormatter.compact(10_000, locale: en), "10K")
        XCTAssertEqual(TokenFormatter.compact(12_300, locale: en), "12.3K")
        XCTAssertEqual(TokenFormatter.compact(1_280_000, locale: en), "1.28M")
        XCTAssertEqual(TokenFormatter.compact(100_000_000, locale: en), "100M")
    }

    func testTokenUsagePrefersQuotaTokensThenProviderTotals() throws {
        let span = try MagpieJSON.decoder.decode(
            QuotaSpan.self, from: Data(#"{"name":"5-hour","amount":1234,"unit":"tokens"}"#.utf8))
        let summary = try fixture("usage", as: UsageSummary.self)
        let windowValue = TokenUsage.value(
            window: span, provider: "anthropic", usage: summary, approximateSource: .today)
        XCTAssertEqual(windowValue?.count, 1_234)
        XCTAssertEqual(windowValue?.source, .window)

        let percentageSpan = try MagpieJSON.decoder.decode(
            QuotaSpan.self, from: Data(#"{"name":"5-hour","amount":100,"unit":"%"}"#.utf8))
        let estimatedValue = TokenUsage.value(
            window: percentageSpan, provider: "anthropic", usage: summary, approximateSource: .today)
        XCTAssertEqual(estimatedValue?.count, 42_000)
        XCTAssertEqual(estimatedValue?.source, .today)
        XCTAssertNil(TokenUsage.value(
            window: percentageSpan, provider: "unknown", usage: summary, approximateSource: .sevenDays))
    }
}
