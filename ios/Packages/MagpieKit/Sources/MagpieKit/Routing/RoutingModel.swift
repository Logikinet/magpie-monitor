import Foundation

public enum SeatState: Equatable, Sendable {
    case trying, answered, rest, idle
}

/// Associated values are data for the UI to format and localize.
public enum SeatStatus: Equatable, Sendable {
    case trying, answered
    case resting(why: String?, until: Date?)
    case remaining(percent: Double, resetDays: Int?)
    case credits(amount: Double, limit: Double?, unit: String?)
    case singleKey, ready
}

public struct SeatGroup: Sendable {
    public let key: String
    public let provider: String?
    public let model: String?
    public let seats: [Seat]
    public var needsSubheader: Bool { seats.count > 1 }
}

public struct RoutingFootCounts: Equatable, Sendable {
    public let requests: Int?
    public let rerouted: Int?
    public let errors: Int?
}

public enum RoutingModel {
    public static func seatKey(id: String, model: String?) -> String {
        id + "\0" + (model ?? "")
    }

    public static func currentRoute(in routes: [Route], pinnedID: Int? = nil) -> Route? {
        if let pinnedID, let route = routes.first(where: { $0.id?.value == pinnedID }) { return route }
        return routes.max { ($0.seq?.value ?? 0) < ($1.seq?.value ?? 0) }
    }

    public static func state(of seat: Seat, in route: Route?) -> SeatState {
        let tries = route?.tries?.elements ?? []
        let exact = tries.filter {
            guard let id = seat.id, let tryID = $0.id else { return false }
            return seatKey(id: id, model: seat.model) == seatKey(id: tryID, model: $0.model)
        }
        let matching = exact.isEmpty ? tries.filter { seat.id != nil && $0.id == seat.id } : exact
        if matching.contains(where: { $0.done == false }) { return .trying }
        if matching.contains(where: { $0.done == true && ($0.status?.value ?? 0) < 400 }) { return .answered }
        return seat.rest == nil ? .idle : .rest
    }

    public static func status(of seat: Seat, in route: Route?, now: Date) -> SeatStatus {
        switch state(of: seat, in: route) {
        case .trying: return .trying
        case .answered: return .answered
        case .rest: return .resting(why: seat.rest?.why, until: seat.rest?.until?.date)
        case .idle: break
        }
        if let used = seat.used?.value, used.isFinite, seat.known == true {
            let reset = seat.usedRenews?.date ?? seat.renews?.elements.first?.date ?? seat.due?.date
            let days = reset.map { Int(ceil(max(0, $0.timeIntervalSince(now)) / 86_400)) }
            return .remaining(percent: min(100, max(0, 100 - used)), resetDays: days)
        }
        if let amount = seat.amount?.value, amount.isFinite {
            return .credits(amount: amount, limit: seat.limit?.value, unit: seat.unit)
        }
        if seat.kind == "key", seat.shared != true { return .singleKey }
        return .ready
    }

    public static func groupedSeats(_ seats: [Seat]) -> [SeatGroup] {
        var groups: [SeatGroup] = []
        for seat in seats {
            let key = (seat.provider ?? "") + "::" + (seat.model ?? "")
            if let index = groups.firstIndex(where: { $0.key == key }) {
                let group = groups[index]
                groups[index] = SeatGroup(key: key, provider: group.provider, model: group.model, seats: group.seats + [seat])
            } else {
                groups.append(SeatGroup(key: key, provider: seat.provider, model: seat.model, seats: [seat]))
            }
        }
        return groups
    }

    public static func footCounts(_ totals: TraceTotals?) -> RoutingFootCounts {
        RoutingFootCounts(requests: totals?.requests?.value, rerouted: totals?.rerouted?.value,
                          errors: totals?.errors?.value)
    }

    /// Red is reserved for failures; unrecognized agents receive a stable palette color.
    public static func agentHue(_ agent: String) -> String {
        let colors = ["claude": "#d97757", "codex": "#6366f1", "gemini": "#0ea5e9",
                      "copilot": "#a855f7", "cursor": "#14b8a6", "opencode": "#eab308",
                      "crush": "#a855f7", "goose": "#84cc16", "pi": "#10b981", "omp": "#38bdf8"]
        if let color = colors[agent.lowercased()] { return color }
        let palette = ["#6366f1", "#0ea5e9", "#a855f7", "#14b8a6", "#eab308", "#84cc16", "#10b981", "#38bdf8"]
        let hash = agent.utf16.reduce(UInt32(0)) { ($0 &* 31) &+ UInt32($1) }
        return palette[Int(hash % UInt32(palette.count))]
    }
}
