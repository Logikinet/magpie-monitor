import Foundation

// All numbers use the user's locale; currency remains the upstream USD estimate.
enum UsageFormat {
    static func cost(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let digits = value >= 100 ? 1 : value >= 1 || value == 0 ? 2 : 3
        return value.formatted(.currency(code: "USD").precision(.fractionLength(digits)))
    }
    static func tokens(_ value: Int?) -> String {
        guard let value else { return "—" }
        let number = Double(value)
        for (scale, suffix) in [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "K")] {
            if number >= scale { return (number / scale).formatted(.number.precision(.fractionLength(0...1))) + suffix }
        }
        return value.formatted()
    }
}
