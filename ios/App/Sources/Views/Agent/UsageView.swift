import SwiftUI
import Charts
import MagpieKit

struct UsageView: View {
    @Bindable var store: AgentStore
    @State private var used = false
    @State private var masked = true
    private let order = ["antigravity", "agy", "dim", "codex", "grok", "kiro", "workbuddy-ai", "our-free-model", "openrouter", "deepseek"]
    private var groups: [(String, [Quota])] {
        Dictionary(grouping: store.usageQuotas, by: { $0.provider ?? "—" }).sorted {
            let a = order.firstIndex(of: $0.key) ?? order.count
            let b = order.firstIndex(of: $1.key) ?? order.count
            return a == b ? $0.key < $1.key : a < b
        }.map { ($0.key, $0.value) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(String(localized: "周期"), selection: $store.period) {
                Text(String(localized: "今天")).tag("today")
                Text(String(localized: "7 天")).tag("7d")
                Text(String(localized: "30 天")).tag("30d")
                Text(String(localized: "全部")).tag("all")
            }.pickerStyle(.segmented)
            Toggle(String(localized: "显示已用"), isOn: $used)
            Toggle(String(localized: "隐藏账号"), isOn: $masked)
            Button(String(localized: "刷新"), systemImage: "arrow.clockwise") { Task { await store.loadUsage() } }.frame(minHeight: 44)
            if let date = store.usageUpdated[store.period] { Text(String(format: String(localized: "更新于 %@"), locale: Locale.current, String(describing: date.formatted(date: .omitted, time: .standard)))).font(.caption) }
            if let error = store.usageError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(DS.Palette.red) }
            if let error = store.routingError { Text(error).foregroundStyle(DS.Palette.red) }
            if store.usage == nil && store.usageError == nil { ProgressView(String(localized: "载入用量")) }
            UsageKPIView(totals: store.usage?.totals)
            ForEach(groups, id: \.0) { provider, accounts in
                VStack(alignment: .leading, spacing: 12) {
                    Text(accounts.first?.name ?? provider).font(.headline).foregroundStyle(providerColor(provider))
                    if let first = accounts.first { AgentQuotaCardView(quota: first, used: used, masked: masked, now: store.now) }
                    if accounts.count > 1 {
                        DisclosureGroup(String(format: String(localized: "更多账号 %@"), locale: Locale.current, String(describing: accounts.count - 1))) {
                            ForEach(Array(accounts.dropFirst().enumerated()), id: \.offset) { _, quota in
                                AgentQuotaCardView(quota: quota, used: used, masked: masked, now: store.now)
                            }
                        }
                    }
                }.routingCard()
            }
            if store.usageQuotas.isEmpty { Text(String(localized: "暂无配额数据")) }
            Text(store.period == "today" ? String(localized: "24 小时请求") : String(localized: "每日请求")).font(.headline)
            Chart(Array((store.usage?.series?.elements ?? []).enumerated()), id: \.offset) { _, point in
                if let date = point.time?.date, let calls = point.calls?.value {
                    BarMark(x: .value(String(localized: "时间"), date), y: .value(String(localized: "请求"), calls))
                        .foregroundStyle(DS.Palette.accent)
                        .accessibilityLabel(date.formatted()).accessibilityValue(calls.formatted())
                }
            }.frame(height: 144)
            breakdown(String(localized: "按 Agent"), store.usage?.agents?.elements ?? [])
            breakdown(String(localized: "按模型"), Array((store.usage?.models?.elements ?? []).sorted { ($0.totals.calls?.value ?? 0) > ($1.totals.calls?.value ?? 0) }.prefix(15)))
            breakdown(String(localized: "账号"), store.usage?.accounts?.elements ?? [], hideNames: masked)
        }.task(id: store.period) { await store.loadUsage() }
    }
    private func providerColor(_ provider: String) -> Color {
        switch provider {
        case "antigravity", "agy": DS.Palette.hex("c084fc")
        case "dim", "codex": DS.Palette.hex("10b981")
        case "kiro": DS.Palette.hex("8b5cf6")
        case "workbuddy", "workbuddy-ai": DS.Palette.hex("06b6d4")
        case "our-free-model": DS.Palette.green
        case "openrouter": DS.Palette.hex("f59e0b")
        case "deepseek": DS.Palette.hex("3b82f6")
        default: DS.Palette.soft
        }
    }
    private func breakdown(_ title: String, _ values: [UsageGroup], hideNames: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if values.isEmpty { Text(String(localized: "暂无用量数据")).foregroundStyle(DS.Palette.soft) }
            ForEach(Array(values.sorted { ($0.totals.calls?.value ?? 0) > ($1.totals.calls?.value ?? 0) }.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(hideNames ? String(localized: "账号已隐藏") : (group.name ?? group.model ?? group.id ?? "—"))
                    Text("\(group.provider ?? "") · \(group.totals.calls?.value.formatted() ?? "—")").font(.caption.monospacedDigit())
                    if let milliseconds = group.totals.decodeMS?.value, milliseconds > 0, let output = group.totals.decodeOut?.value {
                        Text((Double(output) / milliseconds * 1000).formatted(.number.precision(.fractionLength(1))) + " tok/s").font(.caption)
                    } else if let timed = group.totals.timed?.value, timed > 0, let ttft = group.totals.ttftMS?.value {
                        Text((ttft / Double(timed)).formatted(.number.precision(.fractionLength(1))) + " ms").font(.caption)
                    }
                    if let calls = group.totals.calls?.value {
                        ProgressView(value: Double(calls), total: Double(max(1, values.map { $0.totals.calls?.value ?? 0 }.max() ?? 1)))
                    }
                }
            }
        }.routingCard()
    }
}
