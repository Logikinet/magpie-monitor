import SwiftUI
import MagpieKit

struct RuntimesView: View {
    @Environment(AppState.self) private var appState
    let providers: [Provider]
    @AppStorage("runtimeFilter") private var filter = "all"
    @State private var data: CollectorRecord?
    @State private var error: String?
    private let filters = ["all", "run", "tasks", "quota", "none"]
    private var agents: [CollectorRecord] { return data?.records("agents") ?? [] }
    private var activeFilter: String { return filters.contains(filter) ? filter : "all" }
    private var sorted: [CollectorRecord] {
        return agents.sorted { left, right in
            let lhs = rank(left)
            let rhs = rank(right)
            for index in lhs.indices where lhs[index] != rhs[index] { return lhs[index] > rhs[index] }
            return (left.string("name") ?? "") < (right.string("name") ?? "")
        }.filter { agent in
            switch activeFilter {
            case "run": return (agent.number("procs") ?? 0) > 0
            case "tasks": return !agent.records("tasks").isEmpty
            case "quota": return !buckets(agent).isEmpty
            case "none": return agent.flag("installed") != true
            default: return true
            }
        }
    }
    private var low: [String] {
        return agents.flatMap { agent in
            buckets(agent).compactMap { bucket in
                guard let value = bucket.number("remaining_pct"), value < 15 else { return nil }
                return "\(agent.string("name") ?? "—") · \(bucket.string("label") ?? "—") \(value.formatted())%"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error { Text(error).foregroundStyle(DS.Palette.red) }
            if data == nil && error == nil { ProgressView() }
            RuntimeKPIGrid(
                installed: "\(agents.filter { $0.flag("installed") == true }.count)/\(agents.count)",
                processes: whole(agents.reduce(0) { $0 + ($1.number("procs") ?? 0) }),
                tasks: agents.reduce(0) { $0 + $1.records("tasks").count }.formatted(),
                gateways: providers.count.formatted(),
                alerts: low.count.formatted(),
                alertsClear: low.isEmpty
            )
            if !low.isEmpty { lowBanner }
            RuntimeFilterBar(filter: filterBinding)
            ForEach(Array(sorted.enumerated()), id: \.offset) { _, agent in
                RuntimeAgentCard(agent: agent)
            }
            if data != nil && sorted.isEmpty { Text(String(localized: "暂无数据")) }
            RuntimeGatewaySection(providers: providers)
            RuntimeEnvironmentSection(tools: data?.object("env_tools"))
        }
        .onAppear { if !filters.contains(filter) { filter = "all" } }
        .task(id: RefreshContext(profile: appState.currentProfile, isMockMode: appState.isMockMode, isActive: appState.isActive)) {
            data = nil
            error = nil
            guard appState.isActive else { return }
            guard let client = appState.makeCollectorClient() else {
                error = String(localized: "连接 collector 后可查看运行环境。")
                return
            }
            do { data = try await client.runtimes() } catch { self.error = error.localizedDescription }
        }
    }

    private var filterBinding: Binding<String> {
        return Binding(get: { activeFilter }, set: { filter = filters.contains($0) ? $0 : "all" })
    }
    private var lowBanner: some View {
        return Text(String(localized: "以下额度不足 15%") + ": " + low.joined(separator: " / "))
            .font(.subheadline)
            .foregroundStyle(DS.Palette.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .routingCard()
    }
    private func buckets(_ agent: CollectorRecord) -> [CollectorRecord] {
        return agent.object("quota")?.records("buckets") ?? []
    }
    private func activeTasks(_ agent: CollectorRecord) -> Int {
        return agent.records("tasks").filter { task in
            !["done", "completed", "failed"].contains(task.string("status") ?? task.string("state") ?? "")
        }.count
    }
    private func rank(_ agent: CollectorRecord) -> [Double] {
        let meta = agent.object("meta")
        let recent = agent.records("tasks").compactMap { task in
            ISO8601DateFormatter().date(from: task.string("updated_at") ?? task.string("time") ?? "")?.timeIntervalSince1970
        }.max() ?? 0
        let installed: Double = agent.flag("installed") == true ? 1 : 0
        let live: Double = (agent.number("procs") ?? 0) > 0 || activeTasks(agent) > 0 ? 1 : 0
        let history = (meta?.number("tasks_30d") ?? 0) + (meta?.number("sessions_24h") ?? 0)
        return [installed, live, Double(activeTasks(agent)), agent.number("procs") ?? 0, history, recent]
    }
    private func whole(_ value: Double) -> String {
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}

private struct RuntimeFilterBar: View {
    @Binding var filter: String
    private let values = ["all", "run", "tasks", "quota", "none"]
    var body: some View {
        HorizontalChipRow {
            ForEach(values, id: \.self) { item in
                Button(title(item)) { filter = item }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .tint(filter == item ? DS.Palette.accent : .secondary)
                    .accessibilityAddTraits(filter == item ? .isSelected : [])
            }
        }
        .accessibilityLabel(String(localized: "运行时"))
    }
    private func title(_ value: String) -> String {
        switch value {
        case "run": return String(localized: "运行中")
        case "tasks": return String(localized: "任务")
        case "quota": return String(localized: "配额")
        case "none": return String(localized: "未安装")
        default: return String(localized: "全部")
        }
    }
}

struct RuntimeKPIGrid: View {
    let installed: String
    let processes: String
    let tasks: String
    let gateways: String
    let alerts: String
    let alertsClear: Bool
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
            cell(String(localized: "已安装"), installed, DS.Palette.title)
            cell(String(localized: "运行进程"), processes, DS.Palette.green)
            cell(String(localized: "任务"), tasks, DS.Palette.blue)
            cell(String(localized: "模型网关"), gateways, DS.Palette.hex("a78bfa"))
            cell(String(localized: "额度预警"), alerts, alertsClear ? DS.Palette.green : DS.Palette.red)
        }
    }
    private func cell(_ title: String, _ value: String, _ color: Color) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(DS.Palette.soft)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .routingCard()
        .accessibilityElement(children: .combine)
    }
}
