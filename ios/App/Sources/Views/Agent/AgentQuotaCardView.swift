import SwiftUI
import Charts
import MagpieKit

struct AgentQuotaCardView: View {
    let quota: Quota
    let used: Bool
    let masked: Bool
    let now: Date
    private func windowName(_ name: String) -> String {
        switch name.lowercased() {
        case "5 hours", "5-hour", "5h": "5h"
        case "7 days", "weekly", "week", "7d": String(localized: "7 天")
        case "credits": String(localized: "点数")
        default: name
        }
    }
    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .current
        return formatter.localizedString(for: date, relativeTo: now)
    }
    private func dateLine(_ title: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(date.formatted(date: .abbreviated, time: .shortened) + " · " + relative(date))
        }.font(.caption).foregroundStyle(DS.Palette.soft)
    }
    private func progressColor(for percent: Double) -> Color {
        let isCritical = used ? percent >= 85 : percent <= 15
        if isCritical { return DS.Palette.quotaRed }
        let isElevated = used ? percent >= 50 : percent <= 50
        return isElevated ? DS.Palette.quotaOrange : DS.Palette.quotaGreen
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(masked ? String(localized: "账号已隐藏") : (quota.user ?? quota.name ?? "—")).font(.subheadline)
            if let plan = quota.plan { Text(plan).font(.caption) }
            ForEach(Array((quota.windows?.elements ?? []).enumerated()), id: \.offset) { _, window in
                VStack(alignment: .leading, spacing: 8) {
                    let percent = window.usedPercentage.map { used ? $0 : 100 - $0 }
                    HStack {
                        Text(windowName(window.name))
                        Spacer()
                        Text(window.unlimited == true ? String(localized: "无限制") : (percent.map { ($0 / 100).formatted(.percent.precision(.fractionLength(1))) } ?? "—"))
                    }.font(.subheadline.monospacedDigit())
                    if let percent {
                        ProgressView(value: percent, total: 100)
                            .tint(progressColor(for: percent))
                    }
                    if let amount = window.amount?.value {
                        Text("\(amount.formatted()) / \(window.limit?.value.formatted() ?? "—") \(window.unit ?? "")").font(.caption)
                    }
                    if let reset = window.resetsAt?.date {
                        dateLine(String(localized: "重置时间"), reset)
                        if let since = window.holds?.since?.date, reset > since, let usedPercent = window.usedPercentage {
                            let elapsed = min(1, max(0, now.timeIntervalSince(since) / reset.timeIntervalSince(since)))
                            let pace = (usedPercent - elapsed * 100).rounded()
                            Text(String(format: String(localized: "节奏 %@%%"), locale: Locale.current, String(describing: pace.formatted(.number.sign(strategy: .always()))))).font(.caption)
                        }
                    }
                    if let holds = window.holds {
                        Text("Token \(UsageFormat.tokens(holds.tokens?.value)) · \(UsageFormat.cost(holds.cost?.value))").font(.caption)
                    }
                    if let end = window.runsOutAt?.date { dateLine(String(localized: "预计耗尽"), end) }
                }
            }
            if let balance = quota.balance { Text(String(format: String(localized: "余额 %@"), locale: Locale.current, Double(balance).map { UsageFormat.cost($0) } ?? balance)).font(.subheadline.monospacedDigit()) }
            if let trend = quota.balanceTrend {
                Chart(Array((trend.points?.elements ?? []).enumerated()), id: \.offset) { _, point in
                    if let date = point.at?.date, let amount = point.amount?.value {
                        LineMark(x: .value(String(localized: "时间"), date), y: .value(String(localized: "余额"), amount))
                            .foregroundStyle(DS.Palette.accent)
                    }
                }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 32).accessibilityLabel(String(localized: "余额趋势"))
                if let daily = trend.perDay?.value { Text(String(format: String(localized: "每天约 %@"), locale: Locale.current, String(describing: UsageFormat.cost(daily)))).font(.caption) }
                if let end = trend.runsOut?.date { dateLine(String(localized: "预计耗尽"), end) }
            }
            if let daily = quota.daily?.days?.elements.first?.used?.value { Text(String(format: String(localized: "每日用量 %@%%"), locale: Locale.current, String(describing: daily.formatted()))).font(.caption) }
            if let count = quota.resets?.count?.value { Text(String(format: String(localized: "重置次数 %@"), locale: Locale.current, String(describing: count))).font(.caption) }
            if let error = quota.error, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(DS.Palette.red)
                    .padding(12).background(DS.Palette.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
