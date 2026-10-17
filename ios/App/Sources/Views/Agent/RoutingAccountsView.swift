import SwiftUI
import MagpieKit

struct RoutingAccountsView: View {
    let providers: [Provider]
    let quotas: [Quota]
    let now: Date
    @Binding var masked: Bool

    private var hasNoAccounts: Bool { providers.isEmpty && quotas.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(String(localized: "隐藏账号"), isOn: $masked)
            Text(String(localized: "账号与 key")).font(.headline)
            ForEach(Array(providers.enumerated()), id: \.offset) { _, provider in
                providerCard(provider)
            }
            ForEach(Array(quotas.enumerated()), id: \.offset) { _, quota in
                quotaCard(quota)
            }
            if hasNoAccounts {
                Text(String(localized: "暂无账号数据")).foregroundStyle(DS.Palette.dim)
            }
        }
    }

    private func providerCard(_ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(provider.name ?? provider.id ?? "—").font(.subheadline.weight(.semibold))
            Text(providerAccountLabel(provider))
                .font(.caption.monospaced())
                .privacySensitive()
            if let plan = provider.account?.plan {
                Text(plan).font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.elev, in: RoundedRectangle(cornerRadius: DS.Radius.node))
    }

    private func providerAccountLabel(_ provider: Provider) -> String {
        if masked { return String(localized: "账号已隐藏") }
        return provider.account?.user ?? provider.key?.masked ?? "—"
    }

    private func quotaCard(_ quota: Quota) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quota.name ?? quota.provider ?? "—").font(.subheadline)
            Text(quotaAccountLabel(quota)).font(.caption.monospaced()).privacySensitive()
            ForEach(Array((quota.windows?.elements ?? []).enumerated()), id: \.offset) { _, window in
                quotaWindow(window)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.elev, in: RoundedRectangle(cornerRadius: DS.Radius.node))
    }

    private func quotaAccountLabel(_ quota: Quota) -> String {
        masked ? String(localized: "账号已隐藏") : (quota.user ?? "—")
    }

    private func quotaWindow(_ window: QuotaSpan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(windowSummary(window)).font(.caption.monospaced())
            if let used = window.usedPercentage {
                ProgressView(value: 100.0 - Double(used), total: 100.0)
                    .tint(quotaColor(for: used))
            }
            if let reset = window.resetsAt?.date {
                Text(resetSummary(reset))
                    .font(.caption.monospaced())
                    .foregroundStyle(DS.Palette.soft)
            }
        }
    }

    private func windowSummary(_ window: QuotaSpan) -> String {
        let remaining: String
        if window.unlimited == true {
            remaining = String(localized: "无限制")
        } else if let used = window.usedPercentage {
            let fraction = (100.0 - used) / 100.0
            remaining = String(localized: "剩余") + " " + fraction.formatted(.percent.precision(.fractionLength(0)))
        } else {
            remaining = "—"
        }
        return window.name + " · " + remaining
    }

    private func quotaColor(for used: Double) -> Color {
        if used >= 85 { return DS.Palette.quotaRed }
        if used >= 50 { return DS.Palette.quotaOrange }
        return DS.Palette.quotaGreen
    }

    private func resetSummary(_ date: Date) -> String {
        let dateText = date.formatted(date: .abbreviated, time: .shortened)
        let seconds = Int(max(0, date.timeIntervalSince(now)))
        return String(format: String(localized: "重置：%@ · %@ 秒"), locale: Locale.current, dateText, String(seconds))
    }
}
