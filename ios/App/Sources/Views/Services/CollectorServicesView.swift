import SwiftUI
import MagpieKit

struct CollectorServicesView: View {
    let services: [CollectorRecord]
    @State private var scope = "user"
    private let scopes = ["user", "web", "docker", "system", "all"]
    private var filtered: [CollectorRecord] { services.filter { matches($0, scope) } }
    private func matches(_ service: CollectorRecord, _ scope: String) -> Bool {
        if scope == "all" { return true }
        if scope == "web" { return [80.0, 443, 3000, 3426, 5173, 8000, 8080, 8787].contains(service.number("port") ?? -1) }
        if scope == "docker" { return service.string("type") == "docker" || service.flag("docker_proxy") == true }
        return service.string("scope") == scope
    }
    private func title(_ scope: String) -> String {
        switch scope {
        case "user": String(localized: "用户")
        case "web": String(localized: "网页")
        case "system": String(localized: "系统")
        case "all": String(localized: "全部")
        default: "Docker"
        }
    }
    var body: some View {
        List {
            Section {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(scopes, id: \.self) { item in
                            Button { scope = item } label: {
                                Text("\(title(item)) (\(services.filter { matches($0, item) }.count))")
                            }.buttonStyle(.bordered).controlSize(.large).tint(scope == item ? DS.Palette.accent : .secondary)
                                .accessibilityAddTraits(scope == item ? .isSelected : [])
                        }
                    }
                }
            }
            if filtered.isEmpty { Text(String(localized: "暂无数据")).foregroundStyle(.secondary) }
            ForEach(Array(filtered.enumerated()), id: \.offset) { _, service in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(service.string("name") ?? "—").font(.headline)
                        Spacer()
                        Text(service.string("type") == "direct" ? String(localized: "直接进程") : service.string("type") ?? "—").font(.caption).padding(4).background(DS.Palette.chip, in: .capsule)
                    }
                    Text("\(service.string("ip") ?? "—"):\(service.number("port").map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0))) } ?? "—")")
                        .font(.subheadline.monospaced()).textSelection(.enabled)
                    if service.flag("is_self") == true { Text(String(localized: "自身服务")).font(.caption).foregroundStyle(.secondary) }
                    if service.flag("docker_proxy") == true { Text(String(localized: "端口代理")).font(.caption).foregroundStyle(.secondary) }
                    if let uptime = service.object("res")?.number("up_sec") {
                        Text(Duration.seconds(uptime).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("CPU \(service.object("res")?.number("cpu")?.formatted() ?? "—")% · \(service.object("res")?.number("mem_mb")?.formatted() ?? "—") MB")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 8).accessibilityElement(children: .combine)
            }
        }.navigationTitle(String(localized: "服务"))
    }
}
