import XCTest
@testable import MagpieKit

final class RoutingModelTests: XCTestCase {
    private func decode<T: Decodable>(_ json: String, as: T.Type) throws -> T {
        try MagpieJSON.decoder.decode(T.self, from: Data(json.utf8))
    }

    func testNewestAndPinExpiry() throws {
        let routes = try decode(#"[{"id":1,"seq":10},{"id":3,"seq":30},{"id":2,"seq":20}]"#, as: [Route].self)
        XCTAssertEqual(RoutingModel.currentRoute(in: routes)?.id?.value, 3)
        XCTAssertEqual(RoutingModel.currentRoute(in: routes, pinnedID: 1)?.id?.value, 1)
        XCTAssertEqual(RoutingModel.currentRoute(in: routes, pinnedID: 99)?.id?.value, 3)
        XCTAssertNil(RoutingModel.currentRoute(in: []))
        XCTAssertNotEqual(RoutingModel.seatKey(id: "a", model: "bc"), RoutingModel.seatKey(id: "ab", model: "c"))
    }

    func testStatesPreferExactModelThenFallbackAndIgnoreFailures() throws {
        let seat = try decode(#"{"id":"fake-seat","model":"demo","rest":{"why":"failRate"}}"#, as: Seat.self)
        func state(_ tries: String) throws -> SeatState {
            RoutingModel.state(of: seat, in: try decode("{\"tries\":\(tries)}", as: Route.self))
        }
        XCTAssertEqual(try state(#"[{"id":"fake-seat","model":"demo","done":false},{"id":"fake-seat","model":"other","done":true,"status":200}]"#), .trying)
        XCTAssertEqual(try state(#"[{"id":"fake-seat","done":true,"status":200}]"#), .answered)
        XCTAssertEqual(try state(#"[{"id":"fake-seat","done":true,"status":503}]"#), .rest)
        XCTAssertEqual(try state(#"[{"id":"other","done":false}]"#), .rest)
    }

    func testStatusPriorityAndComputedResetDays() throws {
        let now = Date(timeIntervalSince1970: 0)
        let seat = try decode(#"{"id":"fake-seat","model":"demo","known":true,"used":25,"renews":[172800],"amount":10,"kind":"key"}"#, as: Seat.self)
        XCTAssertEqual(RoutingModel.status(of: seat, in: nil, now: now), .remaining(percent: 75, resetDays: 2))
        let trying = try decode(#"{"tries":[{"id":"fake-seat","done":false}]}"#, as: Route.self)
        XCTAssertEqual(RoutingModel.status(of: seat, in: trying, now: now), .trying)
        let rest = try decode(#"{"used":25,"rest":{"why":"failRate"}}"#, as: Seat.self)
        XCTAssertEqual(RoutingModel.status(of: rest, in: nil, now: now), .resting(why: "failRate", until: nil))
        let credits = try decode(#"{"amount":"12","limit":"20","unit":"credits"}"#, as: Seat.self)
        XCTAssertEqual(RoutingModel.status(of: credits, in: nil, now: now), .credits(amount: 12, limit: 20, unit: "credits"))
        let key = try decode(#"{"kind":"key"}"#, as: Seat.self)
        XCTAssertEqual(RoutingModel.status(of: key, in: nil, now: now), .singleKey)
        let unknownQuota = try decode(#"{"used":0}"#, as: Seat.self)
        XCTAssertEqual(RoutingModel.status(of: unknownQuota, in: nil, now: now), .ready)
        let empty = try decode("{}", as: Seat.self)
        XCTAssertEqual(RoutingModel.status(of: empty, in: nil, now: now), .ready)
    }

    func testGroupingCountsAndHues() throws {
        let seats = try decode(#"[{"provider":"demo","model":"one"},{"provider":"other","model":"two"},{"provider":"demo","model":"one"}]"#, as: [Seat].self)
        let groups = RoutingModel.groupedSeats(seats)
        XCTAssertEqual(groups.map(\.key), ["demo::one", "other::two"])
        XCTAssertEqual(groups.map(\.needsSubheader), [true, false])
        let totals = try decode(#"{"requests":"40","rerouted":6,"errors":1}"#, as: TraceTotals.self)
        XCTAssertEqual(RoutingModel.footCounts(totals).requests, 40)
        XCTAssertEqual(RoutingModel.footCounts(totals).rerouted, 6)
        XCTAssertEqual(RoutingModel.footCounts(totals).errors, 1)
        XCTAssertNil(RoutingModel.footCounts(nil).requests)
        XCTAssertEqual(RoutingModel.agentHue("codex"), "#6366f1")
        XCTAssertEqual(RoutingModel.agentHue("unknown"), RoutingModel.agentHue("unknown"))
        for agent in ["omp", "crush", "unknown", "gemini"] {
            XCTAssertFalse(["#f43f5e", "#ef4444", "#ec4899"].contains(RoutingModel.agentHue(agent)))
        }
    }

    func testExpandedFixturesAndLossyRows() throws {
        let trace = try MagpieJSON.decoder.decode(TraceEnvelope.self, from: MockFixtures.data(named: "trace"))
        let routes = try XCTUnwrap(trace.routes?.elements)
        XCTAssertEqual(routes.count, 40)
        XCTAssertEqual(routes.map { $0.seq!.value }, routes.map { $0.seq!.value }.sorted())
        XCTAssertEqual(RoutingModel.currentRoute(in: routes)?.done, false)
        let route = try XCTUnwrap(routes.last)
        XCTAssertEqual(route.order?.elements.count, 16)
        XCTAssertEqual(route.prompt?.parts?.elements.count, 5)
        XCTAssertEqual(route.prompt?.parts?.badCount, 0)
        XCTAssertEqual(route.group?.subs?.elements.first?.in, "demo")
        XCTAssertEqual(route.affinity?.turn?.value, 3)
        XCTAssertTrue(routes.contains { ($0.status?.value ?? 0) >= 400 })
        XCTAssertTrue(routes.contains { ($0.tries?.elements.count ?? 0) > 1 })
        XCTAssertTrue(route.order?.elements.contains { $0.rest != nil } == true)
        XCTAssertTrue(route.order?.elements.contains { $0.fallback == true } == true)
        let groups = try MagpieJSON.decoder.decode(GroupsEnvelope.self, from: MockFixtures.data(named: "groups"))
        XCTAssertEqual(groups.groups?.elements.first?.weights?["demo-claude/demo-sonnet"]?.value, 2)
        XCTAssertEqual(groups.groups?.elements.first?.memberInfo?.badCount, 0)
        XCTAssertEqual(groups.pools?.elements.count, 1)
        let providers = try MagpieJSON.decoder.decode(ProvidersEnvelope.self, from: MockFixtures.data(named: "providers"))
        XCTAssertEqual(providers.providers?.elements.first?.account?.user, "demo-user@example.com")
        XCTAssertEqual(providers.providers?.badCount, 0)
        let quotas = try MagpieJSON.decoder.decode(LossyArray<Quota>.self, from: MockFixtures.data(named: "usage_quotas"))
        XCTAssertEqual(quotas.badCount, 0)
        let quota = try XCTUnwrap(quotas.elements.first)
        XCTAssertEqual(quota.windows?.elements.first?.holds?.tokens?.value, 2000)
        XCTAssertEqual(quota.windows?.elements.first?.runsOut?.value, 7)
        XCTAssertNotNil(quota.windows?.elements.first?.runsOutAt?.date)
        XCTAssertEqual(quota.resets?.each?.elements.first?.window, "weekly")
        XCTAssertEqual(quota.daily?.days?.elements.first?.used?.value, 25)
        XCTAssertEqual(quota.checkin?.streak?.value, 3)
        XCTAssertEqual(quota.balanceTrend?.points?.elements.count, 2)
        let usage = try MagpieJSON.decoder.decode(UsageSummary.self, from: MockFixtures.data(named: "usage"))
        XCTAssertEqual(usage.totals?.timed?.value, 20)
        XCTAssertEqual(usage.totals?.ttftMS?.value, 4200)
        XCTAssertEqual(usage.agents?.elements.first?.totals.calls?.value, 20)
        XCTAssertEqual(usage.accounts?.elements.first?.name, "demo-user@example.com")
        let lossy = try decode(#"{"order":[{"used":"12"},false],"tries":[{"ms":"50"},4]}"#, as: Route.self)
        XCTAssertEqual(lossy.order?.badCount, 1)
        XCTAssertEqual(lossy.tries?.badCount, 1)
        XCTAssertEqual(lossy.tries?.elements.first?.ms?.value, 50)
        let key = try decode(#"{"set":true,"masked":"demo-••••","raw":"discarded","value":"discarded"}"#, as: ProviderKey.self)
        XCTAssertEqual(key.masked, "demo-••••")
    }
}
