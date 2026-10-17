import SwiftUI
import Charts
import MagpieKit

struct CollectorOverviewView: View {
    let sys: CollectorRecord
    let samples: [CollectorRecord]
    let activity: CollectorRecord?
    let tmux: CollectorRecord?
    let services: CollectorRecord?
    let runtimes: CollectorRecord?
    let quotas: [OverviewQuota]
    @State private var pointCount = 24
    private let columns = [GridItem(.adaptive(minimum: 150), alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                stat(String(localized: "负载"), value: sys.numbers("loadavg").map { $0.formatted(.number.precision(.fractionLength(1))) }.joined(separator: " / "), percent: loadPercent)
                stat("CPU", value: percent(sys.number("cpu_usage")) + " · " + (sys.number("cpu_count").map { $0.formatted() } ?? "—") + " " + String(localized: "核心"), percent: sys.number("cpu_usage"))
                stat(String(localized: "内存"), value: storage(sys.object("mem")), percent: sys.object("mem")?.number("percent"))
                stat(String(localized: "磁盘"), value: storage(sys.object("disk")), percent: sys.object("disk")?.number("percent"))
                stat(String(localized: "运行时长"), value: sys.number("uptime").map { Duration.seconds($0).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated)) } ?? "—", percent: nil)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "系统趋势")).font(.headline)
                if samples.isEmpty {
                    Text(String(localized: "等待真实采样")).foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(Array(samples.suffix(pointCount).enumerated()), id: \.offset) { index, sample in
                            if let cpu = sample.number("cpu") { line(index, cpu, "CPU") }
                            if let mem = sample.number("mem") { line(index, mem, String(localized: "内存")) }
                            if let swap = sample.number("swap") { line(index, swap, String(localized: "交换空间")) }
                            if let load = sample.number("load") { line(index, load / maxLoad * 100, String(localized: "负载（归一化）")) }
                        }
                    }
                    .chartXScale(domain: (samples.count < pointCount ? -(pointCount - samples.count) : 0)...max(1, min(samples.count, pointCount) - 1))
                    .chartYScale(domain: 0...100)
                    .chartYAxis { AxisMarks(values: [25, 50, 75]) }
                    .chartForegroundStyleScale([
                        "CPU": DS.Palette.chartCPU, String(localized: "内存"): DS.Palette.chartMemory,
                        String(localized: "交换空间"): DS.Palette.chartSwap, String(localized: "负载（归一化）"): DS.Palette.chartLoad
                    ])
                    .frame(height: 180)
                    .accessibilityLabel(String(localized: "系统趋势"))
                    .gesture(MagnifyGesture().onEnded { value in pointCount = min(24, max(4, Int(Double(pointCount) / Double(value.magnification)))) })
                    Stepper(String(localized: "采样点") + " \(pointCount)", value: $pointCount, in: 4...24)
                        .font(.footnote)
                }
            }.padding(16).background(DS.Palette.panel, in: .rect(cornerRadius: 16))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), alignment: .top)], alignment: .leading, spacing: 16) {
                NavigationLink {
                    List {
                        ForEach(Array((activity?.records("events") ?? []).enumerated()), id: \.offset) { _, event in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(event.string("subject") ?? "—").font(.headline)
                                Text("\(event.string("repo") ?? "—") · \(event.string("short_sha") ?? "—") · \(event.string("author") ?? "—")").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.navigationTitle(String(localized: "活动"))
                } label: {
                    portal(String(localized: "活动"), rows: activity?.records("events").prefix(4).map(activitySummary) ?? [])
                }.buttonStyle(.plain)
                NavigationLink {
                    if let tmux { CollectorTmuxView(topology: tmux) }
                } label: {
                    portal(String(localized: "会话"), rows: tmux?.records("sessions").prefix(4).map(tmuxSummary) ?? [])
                }.buttonStyle(.plain)
                NavigationLink {
                    CollectorServicesView(services: services?.records("services") ?? [], searchText: "", hostname: sys.string("hostname"))
                } label: {
                    portal(String(localized: "服务"), rows: serviceTiles.map { "\($0.string("name") ?? "—") :\($0.number("port")?.formatted() ?? "—") · \(percent($0.object("res")?.number("cpu"))) · \($0.object("res")?.number("mem_mb")?.formatted() ?? "—") MB" })
                }.buttonStyle(.plain)
                NavigationLink { AgentView() } label: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Agent").font(.headline)
                    Text(String(localized: "已安装 / 运行中") + " \(runtimes?.number("total_installed")?.formatted() ?? "—") / \(runtimes?.number("total_running")?.formatted() ?? "—")")
                        .font(.caption).foregroundStyle(.secondary)
                    if quotas.isEmpty { Text(String(localized: "暂无配额数据")).font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(quotas) { quota in
                        let remaining = min(100, max(0, 100 - quota.used))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(quota.provider) · \(quota.window) · \(remaining.formatted())%")
                                .font(.caption)
                            ProgressView(value: remaining, total: 100)
                                .tint(remaining >= 50 ? DS.Palette.green : remaining >= 15 ? DS.Palette.orange : DS.Palette.red)
                                .accessibilityLabel(quota.provider + " · " + quota.window)
                                .accessibilityValue(remaining.formatted() + "%")
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(DS.Palette.panel, in: .rect(cornerRadius: 16))
                }.buttonStyle(.plain)
            }
        }
    }
    private func activitySummary(_ event: CollectorRecord) -> String {
        let time = event.number("ts").map { Date(timeIntervalSince1970: $0).formatted(.relative(presentation: .numeric)) } ?? "—"
        return "\(event.string("repo") ?? "—") · \(event.string("subject") ?? "—")\n\(event.string("author") ?? "—") · \(time)"
    }
    private func tmuxSummary(_ session: CollectorRecord) -> String {
        let attached = session.flag("attached") ?? ((session.number("attached") ?? 0) > 0)
        let status = attached ? String(localized: "已附加") : String(localized: "已分离")
        let agent = session.flag("is_agent") == true ? " · Agent" : ""
        return "\(session.string("name") ?? "—") · \(session.number("windows_count")?.formatted() ?? "—") \(String(localized: "窗口"))\n\(session.string("main_command") ?? "—") · \(status)\(agent)"
    }
    private var loadPercent: Double? {
        guard let load = sys.numbers("loadavg").last, let cores = sys.number("cpu_count"), cores > 0 else { return nil }
        return load / cores * 100
    }
    private var maxLoad: Double { max(2, samples.suffix(pointCount).compactMap { $0.number("load") }.max() ?? 2) }
    private var serviceTiles: [CollectorRecord] {
        var seen = Set<String>()
        return Array((services?.records("services") ?? []).filter {
            let ip = $0.string("ip") ?? ""
            let port = $0.number("port")
            return $0.string("scope") != "system" && $0.flag("paused") != true && !ip.hasPrefix("127.") && ip != "::1" && port != 22000 && port != 5355 && seen.insert("\(port ?? -1):\($0.string("name") ?? "")").inserted
        }.prefix(6))
    }
    private func percent(_ value: Double?) -> String { value.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "—" }
    private func storage(_ value: CollectorRecord?) -> String {
        guard let used = value?.number("used"), let total = value?.number("total"), used >= 0, total >= 0, used < Double(Int64.max), total < Double(Int64.max) else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .binary) + " / " + ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .binary) + " · " + percent(value?.number("percent"))
    }
    private func stat(_ title: String, value: String, percent: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value).font(.subheadline.monospaced()).foregroundStyle((percent ?? 0) > 90 ? DS.Palette.red : (percent ?? 0) >= 75 ? DS.Palette.warn : DS.Palette.text)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(DS.Palette.panel, in: .rect(cornerRadius: 16)).accessibilityElement(children: .combine)
    }
    private func portal(_ title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if rows.isEmpty { Text(String(localized: "暂无数据")).foregroundStyle(.secondary) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in Text(row).font(.subheadline).lineLimit(3) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(DS.Palette.panel, in: .rect(cornerRadius: 16))
    }
    @ChartContentBuilder
    private func line(_ index: Int, _ value: Double, _ series: String) -> some ChartContent {
        if min(samples.count, pointCount) <= 8 {
            PointMark(x: .value(String(localized: "采样点"), index), y: .value(series, value))
                .foregroundStyle(by: .value("", series))
        }
        LineMark(x: .value(String(localized: "采样点"), index), y: .value(series, value), series: .value("", series))
            .foregroundStyle(by: .value("", series))
    }
}
