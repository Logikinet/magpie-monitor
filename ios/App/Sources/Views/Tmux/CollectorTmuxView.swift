import SwiftUI
import MagpieKit

struct CollectorTmuxView: View {
    let topology: CollectorRecord
    @State private var selectedWindows: [String: Int] = [:]
    @State private var filter = "all"
    @State private var captureTarget: String?
    @State private var showsCapture = false
    private var sessions: [CollectorRecord] { topology.records("sessions") }
    private let filters = ["all", "agent", "resumable", "standalone", "attached", "detached"]
    private func title(_ value: String) -> String {
        switch value {
        case "all": String(localized: "全部")
        case "agent": "Agent"
        case "resumable": String(localized: "可恢复")
        case "standalone": String(localized: "独立终端")
        case "attached": String(localized: "已附加")
        default: String(localized: "已分离")
        }
    }
    private func matches(_ session: CollectorRecord, _ value: String) -> Bool {
        let attached = session.flag("attached") ?? ((session.number("attached") ?? 0) > 0)
        switch value {
        case "agent": return session.flag("is_agent") == true
        case "resumable": return session.object("goal")?.string("resume_cmd") != nil
        case "standalone": return session.flag("is_agent") != true
        case "attached": return attached
        case "detached": return !attached
        default: return true
        }
    }
    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                    stat(String(localized: "会话"), Double(sessions.count))
                    stat(String(localized: "窗口"), sessions.reduce(0) { $0 + ($1.number("windows_count") ?? 0) })
                    stat("Pane", topology.object("summary")?.number("panes_total"))
                    stat(String(localized: "已附加 / 已分离"), "\(topology.object("summary")?.number("attached")?.formatted() ?? "—") / \(topology.object("summary")?.number("detached")?.formatted() ?? "—")")
                    stat("Agent", topology.object("summary")?.number("agents"))
                }
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(filters, id: \.self) { item in
                            Button { filter = item } label: { Text("\(title(item)) (\(sessions.filter { matches($0, item) }.count))") }
                                .buttonStyle(.bordered).controlSize(.large).tint(filter == item ? DS.Palette.accent : .secondary)
                                .accessibilityAddTraits(filter == item ? .isSelected : [])
                        }
                    }
                }
            }
            ForEach(Array(sessions.filter { matches($0, filter) }.enumerated()), id: \.offset) { _, session in
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.string("name") ?? "—").font(.headline)
                    Text(session.string("main_command") ?? "—").font(.subheadline.monospaced())
                    HStack {
                        Text(session.flag("is_agent") == true ? "Agent" : title("standalone"))
                        Text(matches(session, "attached") ? title("attached") : title("detached"))
                    }.font(.caption).foregroundStyle(.secondary)
                    if let attach = session.string("attach_cmd") { ShareLink(String(localized: "附加命令"), item: attach) }
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(Array(session.records("windows").enumerated()), id: \.offset) { index, window in
                                Button(window.string("name") ?? String(index)) { selectedWindows[session.string("name") ?? ""] = index }
                                    .buttonStyle(.bordered).controlSize(.large)
                            }
                        }
                    }
                    ForEach(Array(panes(for: session).enumerated()), id: \.offset) { _, pane in
                        if let target = pane.string("target") ?? pane.string("pane") {
                            Button(String(localized: "查看终端") + " · " + target) {
                                captureTarget = target
                                showsCapture = true
                            }.buttonStyle(.bordered).controlSize(.large)
                        }
                    }
                }.padding(.vertical, 8)
            }
            if sessions.isEmpty { Text(String(localized: "暂无数据")).foregroundStyle(.secondary) }
        }
        .navigationTitle("Tmux")
        .fullScreenCover(isPresented: $showsCapture) {
            if let captureTarget { CollectorCaptureView(target: captureTarget) }
        }
    }
    private func panes(for session: CollectorRecord) -> [CollectorRecord] {
        let windows = session.records("windows")
        let selected = selectedWindows[session.string("name") ?? ""] ?? 0
        if windows.indices.contains(selected) { return windows[selected].records("panes") }
        return topology.records("panes").filter { $0.string("session") == session.string("name") }
    }
    private func stat(_ title: String, _ value: Double?) -> some View {
        stat(title, value?.formatted() ?? "—")
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(DS.Palette.panel, in: .rect(cornerRadius: 8))
    }
}
