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
    var body: some View {
        let t = totals
        let tokenValues = [t?.input?.value, t?.output?.value, t?.reasoning?.value, t?.cacheRead?.value].compactMap { $0 }
        let denominator = (t?.input?.value ?? 0) + (t?.cacheRead?.value ?? 0)
        let cache = denominator > 0 && t?.cacheRead != nil ? (Double(t?.cacheRead?.value ?? 0) / Double(denominator)).formatted(.percent.precision(.fractionLength(1))) : "—"
        let samples = t?.timed?.value ?? 0
        let ttft = samples > 0 ? (t?.ttftMS?.value).map {
            ($0 / Double(samples)).formatted(.number.precision(.fractionLength(1))) + " ms"
        } ?? "—" : "—"
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
            metric(String(localized: "请求"), number(t?.calls?.value), (t?.errors?.value ?? 0) > 0 ? String(localized: "错误") + " " + number(t?.errors?.value) : (t?.errors?.value == 0 && (t?.calls?.value ?? 0) > 0 ? "100% OK" : "—"), DS.Palette.accent)
            metric(String(localized: "估算费用"), UsageFormat.cost(t?.cost?.value), (t?.unpriced?.value ?? 0) > 0 ? String(localized: "未定价") + " " + number(t?.unpriced?.value) : "USD", DS.Palette.green)
            metric("Token", UsageFormat.tokens(tokenValues.isEmpty ? nil : tokenValues.reduce(0, +)), "↓\(UsageFormat.tokens(t?.input?.value)) · ↑\(UsageFormat.tokens(t?.output?.value)) · ⚡\(UsageFormat.tokens(t?.reasoning?.value))", DS.Palette.accent)
            metric(String(localized: "缓存命中率"), cache, "", .purple)
            metric(String(localized: "平均首字时间"), ttft, String(localized: "样本") + " " + number(t?.timed?.value), DS.Palette.warn)
        }
    }
}
