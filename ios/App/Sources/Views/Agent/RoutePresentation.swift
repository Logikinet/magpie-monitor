import Foundation
import MagpieKit

enum RoutePresentation {
    static func strategy(_ value: String?) -> String {
        switch value {
        case "order": "顺序"
        case "rotate": "轮转"
        case "usage": "按用量"
        case nil, "": "智能"
        default: value ?? "—"
        }
    }
    static func milliseconds(_ value: Int?) -> String { value.map { "\($0.formatted()) ms" } ?? "—" }
    static func failed(_ route: Route) -> Bool {
        route.error?.isEmpty == false || (route.status?.value ?? 0) >= 400 || (route.tries?.elements ?? []).contains { ($0.status?.value ?? 0) >= 400 }
    }
    static func status(_ seat: Seat, route: Route?, now: Date) -> String {
        switch RoutingModel.status(of: seat, in: route, now: now) {
        case .trying: return "回答中"
        case .answered: return "已回答"
        case .resting(let why, let until):
            let countdown = until.map { " · \(Int(max(0, $0.timeIntervalSince(now)))) 秒" } ?? ""
            return "休息中" + (why.map { " · " + $0 } ?? "") + countdown
        case .remaining(let percent, let days):
            return "剩余 \(percent.formatted(.number.precision(.fractionLength(0))))%" + (days.map { " · \($0) 天后重置" } ?? "")
        case .credits(let amount, let limit, let unit):
            return amount.formatted() + (limit.map { "/\($0.formatted())" } ?? "") + " " + (unit ?? "")
        case .singleKey: return "独立 key"
        case .ready: return "就绪"
        }
    }
}
