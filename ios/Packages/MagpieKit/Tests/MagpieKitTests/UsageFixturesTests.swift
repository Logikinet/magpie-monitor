import XCTest
@testable import MagpieKit

final class UsageFixturesTests: XCTestCase {
    func testProviderDisplayStates() throws {
        let envelope = try MagpieJSON.decoder.decode(ProvidersEnvelope.self, from: MockFixtures.data(named: "providers_usage"))
        let providers = try XCTUnwrap(envelope.providers)
        XCTAssertEqual(providers.badCount, 0)
        XCTAssertEqual(providers.elements.count, 4)
        XCTAssertEqual(providers.elements[0].activeModelsCount?.value, 1)
        XCTAssertNotNil(providers.elements[1].account)
        XCTAssertNil(providers.elements[1].account?.plan)
        XCTAssertEqual(providers.elements[2].key?.masked, "demo-••••")
        XCTAssertEqual(providers.elements[3].off, true)
    }

    func testQuotaWindowsPreserveUnknownAndUnlimited() throws {
        let quotas = try MagpieJSON.decoder.decode(LossyArray<Quota>.self, from: MockFixtures.data(named: "usage_quotas"))
        XCTAssertEqual(quotas.badCount, 0)
        XCTAssertEqual(quotas.elements.count, 4)
        XCTAssertEqual(quotas.elements[0].windows?.elements.map(\.usedPercentage), [25, 55, 88])
        XCTAssertEqual(quotas.elements[1].windows?.elements.first?.usedPercentage, 92)
        XCTAssertEqual(quotas.elements[2].windows?.elements.first?.unlimited, true)
        XCTAssertNotNil(quotas.elements[2].error)
        XCTAssertNil(quotas.elements[3].windows?.elements.first?.usedPercentage)
    }

    func testUsageFetchTimestamp() throws {
        let data = Data(#"{"fetched_at":"2026-10-17T08:00:00Z","calls":4,"timed":2,"ttft_ms":500}"#.utf8)
        let usage = try MagpieJSON.decoder.decode(UsageSummary.self, from: data)
        XCTAssertNotNil(usage.fetchedAt?.date)
        XCTAssertEqual(usage.totals?.timed?.value, 2)
        XCTAssertEqual(usage.totals?.ttftMS?.value, 500)
    }
}
