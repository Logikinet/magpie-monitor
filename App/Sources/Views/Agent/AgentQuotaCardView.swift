import SwiftUI
import MagpieKit

struct AgentQuotaCardView: View {
    let card: QuotaCard

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.mediumSmall) {
            Text(card.name ?? card.provider ?? "提供方").font(.headline)
            if let plan = card.plan { Text(plan).font(.subheadline).foregroundStyle(.secondary) }
            if let error = card.error, !error.isEmpty {
                Label("配额读取失败，请检查提供方连接。", systemImage: "exclamationmark.triangle").font(.subheadline)
            }
            ForEach(Array((card.windows?.elements ?? []).enumerated()), id: \.offset) { _, window in
                if window.unlimited == true {
                    Text("\(window.name) · 无限制").font(.subheadline)
                } else if let amount = window.amount?.value, let limit = window.limit?.value, limit > 0 {
                    QuotaGauge(title: window.name, used: amount, limit: limit)
                    if let unit = window.unit { Text(unit).font(.footnote).foregroundStyle(.secondary) }
                } else if let used = window.used?.value {
                    QuotaGauge(title: window.name, used: used, limit: 100)
                } else {
                    Text("\(window.name) · \(window.display ?? window.used?.value.formatted() ?? "暂无数据")")
                        .font(.subheadline).monospacedDigit()
                }
                if let reset = window.resetsAt?.date {
                    Text("重置时间：\(reset.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let balance = card.balance { Text("余额 \(balance)").font(.subheadline).monospacedDigit() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.medium)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: DS.Radius.card))
    }
}
