import SwiftUI
import MagpieKit

struct RoutingAccountsView: View {
    let providers: [Provider]
    let quotas: [Quota]
    let now: Date
    @Binding var masked: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("隐藏账号", isOn: $masked)
            Text("账号与 key").font(.headline)
            ForEach(Array(providers.enumerated()), id: \.offset) { _, provider in
                VStack(alignment: .leading, spacing: 8) {
                    Text(provider.name ?? provider.id ?? "—").font(.subheadline.weight(.semibold))
                    Text(masked ? "账号已隐藏" : (provider.account?.user ?? provider.key?.masked ?? "—"))
                        .font(.caption.monospaced()).privacySensitive()
                    if let plan = provider.account?.plan { Text(plan).font(.caption) }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(DS.Palette.elev, in: RoundedRectangle(cornerRadius: DS.Radius.node))
            }
            ForEach(Array(quotas.enumerated()), id: \.offset) { _, quota in
                VStack(alignment: .leading, spacing: 8) {
                    Text(quota.name ?? quota.provider ?? "—").font(.subheadline)
                    Text(masked ? "账号已隐藏" : (quota.user ?? "—")).font(.caption.monospaced()).privacySensitive()
                    ForEach(Array((quota.windows?.elements ?? []).enumerated()), id: \.offset) { _, window in
                        Text("\(window.name) · \(window.unlimited == true ? "无限制" : window.usedPercentage.map { "剩余 \((100 - $0).formatted(.number.precision(.fractionLength(0))))%" } ?? "—")").font(.caption.monospaced())
                        if let used = window.usedPercentage {
                            ProgressView(value: 100 - used, total: 100).tint(used >= 85 ? DS.Palette.quotaRed : (used >= 50 ? DS.Palette.quotaOrange : DS.Palette.quotaGreen))
                        }
                        if let reset = window.resetsAt?.date {
                            Text("重置：\(reset.formatted(date: .abbreviated, time: .shortened)) · \(Int(max(0, reset.timeIntervalSince(now)))) 秒")
                                .font(.caption.monospaced()).foregroundStyle(DS.Palette.soft)
                        }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(DS.Palette.elev, in: RoundedRectangle(cornerRadius: DS.Radius.node))
            }
            if providers.isEmpty && quotas.isEmpty { Text("暂无账号数据").foregroundStyle(DS.Palette.dim) }
        }
    }
}
