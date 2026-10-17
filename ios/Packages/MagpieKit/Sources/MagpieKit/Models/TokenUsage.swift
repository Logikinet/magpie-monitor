import Foundation

public enum TokenSource: Equatable, Sendable {
    case window
    case today
    case sevenDays
}

public struct TokenUsageValue: Equatable, Sendable {
    public let count: Int
    public let source: TokenSource
}

public enum TokenUsage {
    /// Quota amounts are consumed counts only when the server labels them in tokens.
    public static func value(
        window: QuotaSpan,
        provider: String,
        usage: UsageSummary?,
        approximateSource: TokenSource
    ) -> TokenUsageValue? {
        if let amount = window.amount?.value,
           amount.isFinite,
           amount >= 0,
           ["token", "tokens"].contains(window.unit?.lowercased() ?? "") {
            return TokenUsageValue(count: Int(amount.rounded()), source: .window)
        }

        // Approximation: the server's nearest supported periods are today for 5h
        // windows and 7d for weekly windows; these totals are wider than the quota.
        let modelTotals = usage?.models?.elements.filter { $0.provider == provider } ?? []
        guard !modelTotals.isEmpty else { return nil }
        let count = modelTotals.reduce(into: 0) { total, model in
            total += model.input?.value ?? 0
            total += model.output?.value ?? 0
        }
        return TokenUsageValue(count: count, source: approximateSource)
    }
}

public enum TokenFormatter {
    public static func compact(_ count: Int, locale: Locale) -> String {
        let positiveCount = max(0, count)
        let value = Double(positiveCount)
        let language = locale.identifier
        if language.hasPrefix("zh") {
            if positiveCount >= 100_000_000 { return compactDecimal(value / 100_000_000, places: 1) + " 亿" }
            if positiveCount >= 10_000 { return compactDecimal(value / 10_000, places: 1) + " 万" }
            return grouped(positiveCount)
        }
        if positiveCount >= 1_000_000 { return compactDecimal(value / 1_000_000, places: 2) + "M" }
        if positiveCount >= 10_000 { return compactDecimal(value / 1_000, places: 1) + "K" }
        return grouped(positiveCount)
    }

    private static func grouped(_ count: Int) -> String {
        let digits = String(count)
        guard digits.count > 3 else { return digits }
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0 && (digits.count - index).isMultiple(of: 3) { result.append(",") }
            result.append(character)
        }
        return result
    }

    private static func compactDecimal(_ value: Double, places: Int = 1) -> String {
        let scale = Int(pow(10, Double(places)))
        let units = Int((value * Double(scale)).rounded())
        let whole = units / scale
        let fraction = units % scale
        guard fraction != 0 else { return String(whole) }
        let digits = String(fraction).leftPadded(to: places)
        return "\(whole).\(digits.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression))"
    }
}

private extension String {
    func leftPadded(to count: Int) -> String {
        String(repeating: "0", count: max(0, count - self.count)) + self
    }
}
