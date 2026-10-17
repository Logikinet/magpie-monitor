import SwiftUI
import MagpieKit

struct RuntimeAgentCard: View {
    let agent: CollectorRecord
    @State private var showsDetail = false
    private var runningCount: Int { return Int((agent.number("procs") ?? 0).rounded()) }
    private var installed: Bool { return agent.flag("installed") == true }
    private var status: String {
        if !installed { return String(localized: "未安装") }
        if runningCount > 0 {
            return String(format: String(localized: "运行中 (%@)"), locale: Locale.current, String(describing: runningCount.formatted()))
        }
        return String(localized: "待机")
    }
    private var buckets: [CollectorRecord] { return agent.object("quota")?.records("buckets") ?? [] }
    private var tasks: [CollectorRecord] { return agent.records("tasks") }
    private var processes: [CollectorRecord] { return agent.records("proc_list") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(agent.string("version") ?? "—").font(.caption.monospaced()).foregroundStyle(DS.Palette.soft).textSelection(.enabled)
            ForEach(Array(processes.enumerated()), id: \.offset) { _, process in
                Text(processLine(process)).font(.caption.monospaced()).textSelection(.enabled)
            }
            if !tasks.isEmpty {
                Text(String(localized: "任务")).font(.subheadline)
                ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                    taskRow(task)
                }
            }
            ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                bucketRow(bucket)
            }
            if let id = agent.string("id"), !id.isEmpty {
                Button(String(localized: "详情")) { showsDetail = true }.frame(minHeight: 44)
            }
        }
        .routingCard()
        .sheet(isPresented: $showsDetail) {
            if let id = agent.string("id") { RuntimeDetailSheet(agentID: id, summary: agent) }
        }
    }

    private var header: some View {
        return HStack(spacing: 8) {
            Circle()
                .fill(runningCount > 0 ? DS.Palette.green : DS.Palette.dim)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(agent.string("name") ?? "—").font(.headline)
            Spacer(minLength: 8)
            Text(status).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(DS.Palette.chip, in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }
    private func processLine(_ process: CollectorRecord) -> String {
        let pid = process.number("pid").map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0))) } ?? "—"
        let cpu = process.number("cpu_pct")?.formatted() ?? "—"
        let memory = process.number("mem_mb")?.formatted() ?? "—"
        return "PID \(pid) · \(process.string("cwd") ?? "—") · \(cpu)% · \(memory) MB"
    }
    private func taskRow(_ task: CollectorRecord) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            Text(task.string("name") ?? task.string("title") ?? task.string("id") ?? "—").font(.subheadline)
            Text("\(task.string("kind") ?? "—") · \(task.string("status") ?? task.string("state") ?? "—") · \(task.string("cwd") ?? task.string("path") ?? "—")")
                .font(.caption)
                .foregroundStyle(DS.Palette.soft)
        }
    }
    private func bucketRow(_ bucket: CollectorRecord) -> some View {
        let remaining = bucket.number("remaining_pct")
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(bucket.string("label") ?? "—") · \(remaining?.formatted() ?? "—")%")
                .font(.caption.monospacedDigit())
            if let remaining {
                ProgressView(value: min(100, max(0, remaining)), total: 100)
                    .tint(quotaTint(remaining))
                    .accessibilityLabel(bucket.string("label") ?? String(localized: "配额"))
            }
        }
    }
    private func quotaTint(_ value: Double) -> Color {
        if value < 15 { return DS.Palette.quotaRed }
        if value <= 50 { return DS.Palette.quotaOrange }
        return DS.Palette.quotaGreen
    }
}
