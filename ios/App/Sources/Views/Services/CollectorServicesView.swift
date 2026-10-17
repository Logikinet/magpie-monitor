import SwiftUI
import MagpieKit

struct CollectorServicesView: View {
    @Environment(AppState.self) private var appState
    let services: [CollectorRecord]
    let searchText: String
    let hostname: String?
    @State private var fetchedHost: String?
    @State private var page = "services"
    @State private var scope = "user"
    private let scopes = ["user", "web", "docker", "system", "all"]
    private let pages = ["services", "tasks", "tailscale"]
    private var query: String { return searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtered: [CollectorRecord] {
        return services.filter { service in
            guard matches(service, scope) else { return false }
            guard !query.isEmpty else { return true }
            let name = service.string("name") ?? ""
            let kind = service.string("type") ?? ""
            return name.localizedCaseInsensitiveContains(query) || kind.localizedCaseInsensitiveContains(query) || address(service).localizedCaseInsensitiveContains(query)
        }
    }
    private func address(_ service: CollectorRecord) -> String {
        guard let port = service.number("port") else { return "—" }
        let portText = port.formatted(.number.grouping(.never).precision(.fractionLength(0)))
        let ip = service.string("ip") ?? ""
        let host = displayHost(ip)
        return "\(host):\(portText)"
    }
    private func displayHost(_ ip: String) -> String {
        if ip == "::1" || ip.hasPrefix("127.") { return "127.0.0.1" }
        if ip.isEmpty || ip == "0.0.0.0" || ip == "::" {
            let name = (hostname ?? fetchedHost)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "—" : name
        }
        if ip.contains(":") { return "[\(ip)]" }
        return ip
    }
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
    private func pageTitle(_ page: String) -> String {
        switch page {
        case "tasks": return String(localized: "任务")
        case "tailscale": return "Tailscale"
        default: return String(localized: "服务")
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HorizontalChipRow {
                ForEach(pages, id: \.self) { item in
                    Button(pageTitle(item)) { page = item }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .tint(page == item ? DS.Palette.accent : .secondary)
                        .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            Group {
                if page == "services" { serviceList }
                else { CollectorServiceDetailsView(kind: page) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: hostname ?? "") { await loadHost() }
    }
    private func loadHost() async {
        let provided = hostname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard provided.isEmpty, let client = appState.makeCollectorClient() else { return }
        fetchedHost = try? await client.sys().string("hostname")
    }
    private var serviceList: some View {
        return List {
            Section {
                HorizontalChipRow {
                    ForEach(scopes, id: \.self) { item in
                        Button { scope = item } label: {
                            Text("\(title(item)) (\(services.filter { matches($0, item) }.count))")
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .tint(scope == item ? DS.Palette.accent : .secondary)
                        .accessibilityAddTraits(scope == item ? .isSelected : [])
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
                    Text(address(service))
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
