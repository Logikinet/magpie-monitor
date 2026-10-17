import SwiftUI

enum DS {
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let mediumSmall: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }

    enum Radius {
        static let small: CGFloat = 8
        static let card: CGFloat = 12
    }

    enum StatusKind {
        case ok
        case warning
        case error
        case neutral
        case insecure
        case mock

        var color: Color {
            switch self {
            case .ok: .green
            case .warning, .insecure: .orange
            case .error: .red
            case .neutral, .mock: .secondary
            }
        }

        var systemImage: String {
            switch self {
            case .ok: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.circle.fill"
            case .neutral: "minus.circle"
            case .insecure: "lock.open.fill"
            case .mock: "play.rectangle"
            }
        }

        var label: String {
            switch self {
            case .ok: "正常"
            case .warning: "注意"
            case .error: "错误"
            case .neutral: "未知"
            case .insecure: "不安全（HTTP）"
            case .mock: "模拟数据"
            }
        }
    }
}

struct StatusBadge: View {
    let kind: DS.StatusKind
    var text: String? = nil

    private var label: String { text ?? kind.label }

    var body: some View {
        Label(label, systemImage: kind.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(kind.color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    var caption: String? = nil
    let systemImage: String

    private var accessibilityText: String {
        ([title, value] + (caption.map { [$0] } ?? [])).joined(separator: "，")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.medium)
        .background(
            .background.secondary,
            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct EmptyStateView: View {
    let title: String
    var description: String? = nil
    var systemImage: String = "tray"

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let description {
                Text(description)
            }
        }
        .accessibilityLabel(description.map { "\(title)，\($0)" } ?? title)
    }
}

struct QuotaGauge: View {
    let title: String
    let used: Double
    let limit: Double
    var subtitle: String? = nil

    private var safeUsed: Double { used.isFinite ? max(0, used) : 0 }
    private var safeLimit: Double { limit.isFinite ? max(0, limit) : 0 }
    private var fraction: Double { safeLimit > 0 ? min(safeUsed / safeLimit, 1) : 0 }
    private var percentage: Int { Int((fraction * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer(minLength: DS.Spacing.small)
                Text("\(percentage)%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .tint(percentage >= 100 ? .orange : .accentColor)
            Text(subtitle ?? "已用 \(Int(safeUsed.rounded()))%")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(DS.Spacing.medium)
        .background(
            .background.secondary,
            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)配额")
        .accessibilityValue("\(subtitle ?? "已用 \(Int(safeUsed.rounded()))%")，\(percentage)%")
    }
}

struct InsecureBadge: View {
    var body: some View { StatusBadge(kind: .insecure) }
}

struct MockBadge: View {
    var body: some View { StatusBadge(kind: .mock, text: "Mock data") }
}

#Preview("状态") {
    VStack(alignment: .leading, spacing: DS.Spacing.small) {
        StatusBadge(kind: .ok)
        StatusBadge(kind: .warning)
        StatusBadge(kind: .error)
        InsecureBadge()
        MockBadge()
    }
    .padding()
}

#Preview("指标卡片") {
    MetricCard(title: "活动请求", value: "1,284", caption: "过去 24 小时", systemImage: "arrow.left.arrow.right")
        .padding()
}

#Preview("区块标题") {
    SectionHeader(title: "配额", subtitle: "按周期查看使用情况")
        .padding()
}

#Preview("空状态") {
    EmptyStateView(title: "暂无数据", description: "连接服务器后会显示监控信息。")
}

#Preview("配额") {
    VStack(spacing: DS.Spacing.medium) {
        QuotaGauge(title: "5 小时", used: 42, limit: 100)
        QuotaGauge(title: "每周", used: 720, limit: 1000)
    }
    .padding()
}
