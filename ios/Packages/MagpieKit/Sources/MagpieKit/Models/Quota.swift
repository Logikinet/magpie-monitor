import Foundation

public struct QuotaList: Decodable {
    public let object: String?
    public let data: LossyArray<Quota>
}

public struct Quota: Decodable {
    public let provider: String?
    public let name: String?
    public let kind: String?
    public let plan: String?
    public let user: String?
    public let windows: LossyArray<QuotaSpan>?
    public let balance: String?
    public let balanceSplit: LossyArray<BalancePart>?
    public let error: String?
    public let asOf: MagpieDate?
    public let readDeferred: Bool?
    public let readAt: MagpieDate?
    public let until: MagpieDate?

    public var fiveHourWindow: QuotaSpan? {
        windows?.elements.first { window in
            let name = window.name.normalizedWindow
            return name.contains("5h") || name.contains("5hour") || name.contains("fivehour")
        }
    }

    public var weeklyWindow: QuotaSpan? {
        windows?.elements.first { window in
            let name = window.name.normalizedWindow
            return name.contains("week") || name.contains("7d")
        }
    }
}

public struct QuotaSpan: Decodable {
    public let unlimited: Bool?
    public let name: String
    public let used: FlexibleDouble?
    public let remaining: FlexibleDouble?
    public let resetsAt: MagpieDate?
    public let display: String?
    public let amount: FlexibleDouble?
    public let limit: FlexibleDouble?
    public let unit: String?
    public let pool: String?
    public let holds: WindowHolds?
    public let holdsWhy: String?

    /// `used` and `remaining` are percentages; `amount` and `limit` are counts.
    public var usedPercentage: Double? {
        guard unlimited != true else { return nil }
        let percentage: Double
        if let used = used?.value, used.isFinite {
            percentage = used
        } else if let remaining = remaining?.value, remaining.isFinite {
            percentage = 100 - remaining
        } else if let amount = amount?.value, amount.isFinite,
                  let limit = limit?.value, limit.isFinite, limit > 0 {
            percentage = amount / limit * 100
        } else {
            return nil
        }
        return min(100, max(0, percentage))
    }
}

public struct WindowHolds: Decodable {
    public let requests: FlexibleInt?
    public let tokens: FlexibleInt?
    public let cost: FlexibleDouble?
}

public struct BalancePart: Decodable {
    public let name: String?
    public let balance: String?
    public let amount: FlexibleDouble?
}

/// Display fields from provider.SubscriptionQuota, returned by `/quotas/cards`.
public struct QuotaCardList: Decodable {
    public let object: String?
    public let data: LossyArray<QuotaCard>
}

public struct QuotaCard: Decodable {
    public let provider: String?
    public let name: String?
    public let icon: String?
    public let plan: String?
    public let accessSKU: String?
    public let user: String?
    public let windows: LossyArray<QuotaSpan>?
    public let balance: String?
    public let balanceParts: LossyArray<BalancePart>?
    public let balanceSplit: LossyArray<BalancePart>?
    public let until: MagpieDate?
    public let error: String?
    public let pluginError: Bool?

    enum CodingKeys: String, CodingKey {
        case provider, name, icon, plan, user, windows, balance, balanceParts, balanceSplit, until, error, pluginError
        case accessSKU = "accessSku"
    }
}

private extension String {
    var normalizedWindow: String {
        lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
