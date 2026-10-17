import SwiftUI
import UIKit
import MagpieKit

enum DS {
    enum Palette {
        static func hex(_ hex: String) -> Color { Color(uiColor: ui(hex)) }
        private static func ui(_ hex: String) -> UIColor {
            let value = UInt32(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        }
        private static func dynamic(_ dark: String, _ light: String) -> Color {
            Color(uiColor: UIColor { traits in ui(traits.userInterfaceStyle == .dark ? dark : light) })
        }
        static let bg = dynamic("0a0a0a", "f2f2f7")
        static let elev = dynamic("141414", "ffffff")
        static let panel = dynamic("131313", "fafafa")
        static let deep = dynamic("101010", "ececec")
        static let hover = dynamic("1f1f1f", "e9e9e9")
        static let active = dynamic("262626", "e2e2e2")
        static let border = dynamic("222222", "e0e0e0")
        static let borderSoft = dynamic("1f1f1f", "e4e4e4")
        static let borderFaint = dynamic("1a1a1a", "eaeaea")
        static let chip = dynamic("1c1c1e", "ffffff")
        static let chipOn = dynamic("f2f2f2", "1f1f1f")
        static let chipText = dynamic("111111", "ffffff")
        static let accent = dynamic("0a84ff", "0066cc")
        static let red = dynamic("e06c6c", "b33939")
        static let warn = dynamic("f0b662", "8a5800")
        static let green = dynamic("6ec89a", "1e7d4f")
        static let orange = dynamic("e0884c", "a85413")
        static let blue = dynamic("8ab4f8", "2b6cb0")
        static let violet = dynamic("9d8cf5", "6c5ce7")
        static let chartCPU = dynamic("6ea8dc", "3572b0")
        static let chartLoad = dynamic("6ec89a", "1e7d4f")
        static let chartMemory = dynamic("e0a84c", "a8731a")
        static let chartSwap = dynamic("b48ead", "8d6a9e")
        static let chartGrid = dynamic("1c1c1c", "e4e4e4")
        static let title = dynamic("f2f2f2", "111111")
        static let hi = dynamic("eeeeee", "1a1a1a")
        static let text = dynamic("d6d6d6", "242424")
        static let mid = dynamic("c9c9c9", "333333")
        static let soft = dynamic("b0b0b0", "464646")
        static let dim = dynamic("909090", "575757")
        static let faint = dynamic("8a8a8a", "666666")
        static let ghost = dynamic("777777", "757575")
        static let dead = dynamic("666666", "8f8f8f")
        static let kSystem = dynamic("a855f7", "a855f7")
        static let kTools = dynamic("818cf8", "818cf8")
        static let kFiles = dynamic("38bdf8", "38bdf8")
        static let kResults = dynamic("f43f5e", "f43f5e")
        static let kChat = dynamic("a5b4fc", "a5b4fc")
        static let kMemory = dynamic("f59e0b", "f59e0b")
        static let quotaGreen = dynamic("22c55e", "22c55e")
        static let quotaOrange = dynamic("f59e0b", "f59e0b")
        static let quotaRed = dynamic("ef4444", "ef4444")
        static let kFree = Color.gray.opacity(0.12)
        static func agent(_ name: String) -> Color { hex(RoutingModel.agentHue(name)) }
    }

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let mediumSmall: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }

    enum Radius {
        static let small: CGFloat = 8
        static let card: CGFloat = 16
        static let node: CGFloat = 10
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
