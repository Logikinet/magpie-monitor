import XCTest
@testable import MagpieKit

final class RouteWeightsTests: XCTestCase {
    func testOrderSchedulingMetricsDecodeNumbersAndStrings() throws {
        let data = Data(#"{"order":[{"provider":"demo","used":"25","amount":25,"limit":"100","unit":"requests","pace":"3.5","tokens":120,"rank":"2","turn":true},{}]}"#.utf8)
        let route = try MagpieJSON.decoder.decode(Route.self, from: data)
        let candidate = try XCTUnwrap(route.order?.elements.first)
        XCTAssertEqual(candidate.used?.value, 25)
        XCTAssertEqual(candidate.amount?.value, 25)
        XCTAssertEqual(candidate.limit?.value, 100)
        XCTAssertEqual(candidate.unit, "requests")
        XCTAssertEqual(candidate.pace?.value, 3.5)
        XCTAssertEqual(candidate.tokens?.value, 120)
        XCTAssertEqual(candidate.rank?.value, 2)
        XCTAssertEqual(candidate.turn, true)
        XCTAssertEqual(route.order?.elements.count, 2)
        XCTAssertNil(route.order?.elements.last?.used)
    }
}
