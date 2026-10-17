import Foundation
import MagpieKit

enum RoutePresentation {
    static func strategy(_ value: String?) -> String {
        switch value {
        case "order": String(localized: "顺序")
        case "rotate": String(localized: "轮转")
        case "usage": String(localized: "按用量")
        case nil, "": String(localized: "智能")
        default: value ?? "—"
        }
    }
    static func milliseconds(_ value: Int?) -> String {
        value.map { duration(milliseconds: Double($0)) } ?? "—"
    }
    static func duration(milliseconds: Double) -> String {
        guard milliseconds.isFinite, milliseconds >= 0 else { return "—" }
        if milliseconds < 1_000 { return "\(Int(milliseconds.rounded()).formatted()) ms" }
        let seconds = milliseconds / 1_000
        if seconds < 60 { return seconds.formatted(.number.precision(.fractionLength(1))) + String(localized: " 秒") }
        let minutes = Int(seconds) / 60
        if minutes < 60 { return String(format: String(localized: "%@ 分 %@ 秒"), locale: Locale.current, String(describing: minutes), String(describing: Int(seconds) % 60)) }
        return String(format: String(localized: "%@ 小时 %@ 分"), locale: Locale.current, String(describing: minutes / 60), String(describing: minutes % 60))
    }
    static func elapsed(_ start: Date?, now: Date = .now) -> String {
        guard let start else { return "—" }
        return duration(milliseconds: max(0, now.timeIntervalSince(start) * 1_000))
    }
    static func failed(_ route: Route) -> Bool {
        route.error?.isEmpty == false || (route.status?.value ?? 0) >= 400 || (route.tries?.elements ?? []).contains { ($0.status?.value ?? 0) >= 400 }
    }
    static func status(_ seat: Seat, route: Route?, now: Date) -> String {
        switch RoutingModel.status(of: seat, in: route, now: now) {
        case .trying: return String(localized: "回答中")
        case .answered: return String(localized: "已回答")
        case .resting(let why, let until):
            let countdown = until.map { String(format: String(localized: " · %@ 秒"), locale: Locale.current, String(describing: Int(max(0, $0.timeIntervalSince(now))))) } ?? ""
            return String(localized: "休息中") + (why.map { " · " + $0 } ?? "") + countdown
        case .remaining(let percent, let days):
            return String(format: String(localized: "剩余 %@%%"), locale: Locale.current, String(describing: percent.formatted(.number.precision(.fractionLength(0))))) + (days.map { String(format: String(localized: " · %@ 天后重置"), locale: Locale.current, String(describing: $0)) } ?? "")
        case .credits(let amount, let limit, let unit):
            return amount.formatted() + (limit.map { "/\($0.formatted())" } ?? "") + " " + (unit ?? "")
        case .singleKey: return String(localized: "独立 key")
        case .ready: return String(localized: "就绪")
        }
    }
}
