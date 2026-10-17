import Foundation

/// Collector fields vary by platform and installed tools. Preserve unknown fields and absent metrics.
public struct CollectorRecord: Decodable, Sendable, Equatable {
    public let fields: [String: JSONValue]
    public init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }
    public func string(_ key: String) -> String? {
        guard case .string(let value) = fields[key] else { return nil }; return value
    }
    public func number(_ key: String) -> Double? {
        switch fields[key] {
        case .number(let value): return value.isFinite ? value : nil
        case .string(let value): return Double(value).flatMap { $0.isFinite ? $0 : nil }
        default: return nil
        }
    }
    public func flag(_ key: String) -> Bool? {
        guard case .bool(let value) = fields[key] else { return nil }; return value
    }
    public func object(_ key: String) -> CollectorRecord? {
        guard case .object(let value) = fields[key] else { return nil }; return CollectorRecord(fields: value)
    }
    public func records(_ key: String) -> [CollectorRecord] {
        guard case .array(let values) = fields[key] else { return [] }
        return values.compactMap { if case .object(let fields) = $0 { return CollectorRecord(fields: fields) }; return nil }
    }
    public func numbers(_ key: String) -> [Double] {
        guard case .array(let values) = fields[key] else { return [] }
        return values.compactMap { if case .number(let number) = $0, number.isFinite { return number }; return nil }
    }
    private init(fields: [String: JSONValue]) { self.fields = fields }
}
