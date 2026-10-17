import SwiftUI
import MagpieKit

struct RuntimeDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let agentID: String
    let summary: CollectorRecord
    @State private var detail: CollectorRecord?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(DS.Palette.red) }
                if detail == nil && error == nil { ProgressView() }
                ForEach(rows, id: \.title) { row in
                    LabeledContent(row.title) {
                        Text(row.value).textSelection(.enabled).multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle(summary.string("name") ?? agentID)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
            .task(id: agentID) { await load() }
        }
    }

    private var rows: [DetailRow] {
        let source = detail ?? summary
        var items = [
            DetailRow(title: String(localized: "版本"), value: source.string("version") ?? summary.string("version") ?? "—"),
            DetailRow(title: String(localized: "已安装"), value: (source.flag("installed") ?? summary.flag("installed")) == true ? String(localized: "是") : String(localized: "否")),
            DetailRow(title: String(localized: "运行进程"), value: whole(source.number("procs") ?? summary.number("procs"))),
        ]
        if let bin = source.string("bin") ?? summary.string("bin") {
            items.append(DetailRow(title: String(localized: "可执行文件"), value: bin))
        }
        let meta = source.object("meta") ?? summary.object("meta")
        if let sessions = meta?.number("sessions_24h") {
            items.append(DetailRow(title: String(localized: "会话"), value: whole(sessions)))
        }
        return items
    }
    private func whole(_ value: Double?) -> String {
        return value?.formatted(.number.precision(.fractionLength(0))) ?? "—"
    }
    private func load() async {
        detail = nil
        error = nil
        guard let client = appState.makeCollectorClient() else {
            error = String(localized: "连接 collector 后可查看运行环境。")
            return
        }
        do { detail = try await client.runtime(id: agentID) } catch { self.error = error.localizedDescription }
    }
}

private struct DetailRow: Identifiable {
    let title: String
    let value: String
    var id: String { return title }
}
