import SwiftUI
import MagpieKit

struct UsageKPIView: View {
    let totals: UsageTotals?
    private func number(_ value: Int?) -> String { value?.formatted() ?? "—" }
    private func metric(_ title: String, _ value: String, _ detail: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(DS.Palette.soft)
            Text(value).font(.title2.monospacedDigit()).foregroundStyle(color)
            Text(detail).font(.caption).foregroundStyle(DS.Palette.soft)
        }.frame(maxWidth: .infinity, alignment: .leading).routingCard()
    }
    private var requestDetail: String {
        let errors = totals?.errors?.value ?? 0
        if errors > 0 { return String(localized: "错误") + " " + number(errors) }
        if errors == 0 && (totals?.calls?.value ?? 0) > 0 { return "100% OK" }
        return "—"
    }
    private var costDetail: String {
        let unpriced = totals?.unpriced?.value ?? 0
        return unpriced > 0 ? String(localized: "未定价") + " " + number(unpriced) : "USD"
    }
    var body: some View {
        let t = totals
        let tokenValues = [t?.input?.value, t?.output?.value, t?.reasoning?.value, t?.cacheRead?.value].compactMap { $0 }
        let inputTokens: Int = t?.input?.value ?? 0
        let cacheTokens: Int = t?.cacheRead?.value ?? 0
        let denominator: Double = Double(inputTokens) + Double(cacheTokens)
        let cache: String
        if denominator > 0, t?.cacheRead != nil {
            cache = (Double(cacheTokens) / denominator).formatted(.percent.precision(.fractionLength(1)))
        } else {
            cache = "—"
        }
        let samples = t?.timed?.value ?? 0
        let ttft = samples > 0 ? (t?.ttftMS?.value).map {
            ($0 / Double(samples)).formatted(.number.precision(.fractionLength(1))) + " ms"
        } ?? "—" : "—"
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
            metric(String(localized: "请求"), number(t?.calls?.value), requestDetail, DS.Palette.accent)
            metric(String(localized: "估算费用"), UsageFormat.cost(t?.cost?.value), costDetail, DS.Palette.green)
            metric("Token", UsageFormat.tokens(tokenValues.isEmpty ? nil : tokenValues.reduce(0, +)), "↓\(UsageFormat.tokens(t?.input?.value)) · ↑\(UsageFormat.tokens(t?.output?.value)) · ⚡\(UsageFormat.tokens(t?.reasoning?.value))", DS.Palette.accent)
            metric(String(localized: "缓存命中率"), cache, "", .purple)
            metric(String(localized: "平均首字时间"), ttft, String(localized: "样本") + " " + number(t?.timed?.value), DS.Palette.warn)
        }
    }
}
