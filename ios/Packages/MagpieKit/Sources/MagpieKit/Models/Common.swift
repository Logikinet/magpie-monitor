import Foundation

public struct FlexibleDouble: Decodable, Equatable, Sendable {
    public let value: Double

    public init(_ value: Double) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let string = try? container.decode(String.self), let number = Double(string) {
            value = number
        } else {
            throw DecodingError.typeMismatch(
                Double.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected a number or numeric string")
            )
        }
    }
}

public struct FlexibleInt: Decodable, Equatable, Sendable {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
        } else if let number = try? container.decode(Double.self),
                  number.isFinite,
                  number.rounded() == number,
                  number >= Double(Int.min),
                  number < Double(Int.max) {
            value = Int(number)
        } else if let string = try? container.decode(String.self), let number = Int(string) {
            value = number
        } else {
            throw DecodingError.typeMismatch(
                Int.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected an integer or numeric string")
            )
        }
    }
}

public struct LossyArray<Element: Decodable>: Decodable {
    public let elements: [Element]
    public let badCount: Int

    public init(_ elements: [Element], badCount: Int = 0) {
        self.elements = elements
        self.badCount = badCount
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Element] = []
        var failures = 0

        while !container.isAtEnd {
            let elementDecoder = try container.superDecoder()
            do {
                decoded.append(try Element(from: elementDecoder))
            } catch {
                failures += 1
            }
        }

        elements = decoded
        badCount = failures
    }
}

public struct MagpieDate: Decodable, Equatable, Sendable {
    public let date: Date?
    public let rawString: String?

    public init(date: Date?, rawString: String? = nil) {
        self.date = date
        self.rawString = rawString
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let timestamp = try? container.decode(Double.self) {
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
            date = Date(timeIntervalSince1970: seconds)
            rawString = nil
            return
        }

        let raw = try container.decode(String.self)
        rawString = raw
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        date = fractional.date(from: raw) ?? standard.date(from: raw)
    }
}

public enum MagpieJSON {
    public static var decoder: JSONDecoder {
        JSONDecoder()
    }
}

public struct GatewayHello: Decodable {
    public let name: String?
    public let version: String?
}

public struct UsageTotals: Decodable {
    public let calls: FlexibleInt?
    public let errors: FlexibleInt?
    public let retried: FlexibleInt?
    public let loops: FlexibleInt?
    public let input: FlexibleInt?
    public let output: FlexibleInt?
    public let cacheRead: FlexibleInt?
    public let cacheWrite: FlexibleInt?
    public let reasoning: FlexibleInt?
    public let cost: FlexibleDouble?
    public let unpriced: FlexibleInt?
    public let tokens: FlexibleInt?
    public let timed: FlexibleInt?
    public let ttftMS: FlexibleDouble?
    public let decodeMS: FlexibleDouble?
    public let decodeOut: FlexibleInt?
    public let decodeN: FlexibleInt?

    enum CodingKeys: String, CodingKey {
        case calls, errors, retried, loops, input, output, cost, unpriced, tokens, reasoning
        case timed
        case ttftMS = "ttft_ms"
        case decodeMS = "decode_ms"
        case decodeOut = "decode_out"
        case decodeN = "decode_n"
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }
}

public struct UsageSummary: Decodable {
    public let bucket: String?
    public let period: String?
    public let since: MagpieDate?
    public let totals: UsageTotals?
    public let models: LossyArray<UsageModelTotal>?
    public let series: LossyArray<SeriesPoint>?
    public let callerKeys: LossyArray<CallerKeyGroup>?
    public let agents: LossyArray<UsageGroup>?
    public let accounts: LossyArray<UsageGroup>?

    private enum CodingKeys: String, CodingKey {
        case bucket, period, since, series, callerKeys, models, agents, accounts
        case calls, errors, retried, loops, input, output, cost, unpriced, tokens, reasoning
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bucket = try container.decodeIfPresent(String.self, forKey: .bucket)
        period = try container.decodeIfPresent(String.self, forKey: .period)
        since = try container.decodeIfPresent(MagpieDate.self, forKey: .since)
        series = try container.decodeIfPresent(LossyArray<SeriesPoint>.self, forKey: .series)
        callerKeys = try container.decodeIfPresent(LossyArray<CallerKeyGroup>.self, forKey: .callerKeys)
        models = try container.decodeIfPresent(LossyArray<UsageModelTotal>.self, forKey: .models)

        agents = try container.decodeIfPresent(LossyArray<UsageGroup>.self, forKey: .agents)
        accounts = try container.decodeIfPresent(LossyArray<UsageGroup>.self, forKey: .accounts)
        totals = try UsageTotals(from: decoder)
    }
}

/// A usage model group; provider IDs let quota cards aggregate model totals.
public typealias UsageModelTotal = UsageGroup

/// Usage totals are flattened into each group and time bucket by the server.
public struct UsageGroup: Decodable {
    public let id: String?
    public let name: String?
    public let sub: String?
    public let icon: String?
    public let provider: String?
    public let model: String?
    public let host: String?
    public let account: String?
    public let totals: UsageTotals
    public var input: FlexibleInt? { totals.input }
    public var output: FlexibleInt? { totals.output }

    private enum CodingKeys: String, CodingKey { case id, name, sub, icon, provider, model, host, account }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        sub = try c.decodeIfPresent(String.self, forKey: .sub)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        host = try c.decodeIfPresent(String.self, forKey: .host)
        account = try c.decodeIfPresent(String.self, forKey: .account)
        totals = try UsageTotals(from: decoder)
    }
}

public struct SeriesPoint: Decodable {
    public let label: String?
    public let time: MagpieDate?
    public let by: [String: [String: UsageTotals]]?
    public let totals: UsageTotals
    public var calls: FlexibleInt? { totals.calls }
    public var cost: FlexibleDouble? { totals.cost }
    public var tokens: FlexibleInt? { totals.tokens }
    private enum CodingKeys: String, CodingKey { case label, time, by }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        time = try c.decodeIfPresent(MagpieDate.self, forKey: .time)
        by = try c.decodeIfPresent([String: [String: UsageTotals]].self, forKey: .by)
        totals = try UsageTotals(from: decoder)
    }
}

public struct CallerKeyGroup: Decodable {
    public let id: String?
    public let callerKeyID: String?
    public let callerKeyName: String?
    public let calls: FlexibleInt?
    public let errors: FlexibleInt?
    public let input: FlexibleInt?
    public let output: FlexibleInt?
    public let cost: FlexibleDouble?

    enum CodingKeys: String, CodingKey {
        case id, calls, errors, input, output, cost
        case callerKeyID = "callerKeyId"
        case callerKeyName = "callerKeyName"
    }
}

extension LossyArray: Sendable where Element: Sendable {}
