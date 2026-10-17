import Foundation

public enum SSHAuthKind: String, Codable, Sendable {
    case privateKey, password
}

public struct ProfileConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var gatewayURL: String
    public var webURL: String?
    public var sshHost: String
    public var sshPort: Int
    public var sshUser: String
    public var sshAuthKind: SSHAuthKind
    public var refreshInterval: TimeInterval

    public init(id: UUID = UUID(), name: String, gatewayURL: String, webURL: String? = nil,
                sshHost: String = "", sshPort: Int = 22, sshUser: String = "",
                sshAuthKind: SSHAuthKind = .privateKey, refreshInterval: TimeInterval = 20) {
        self.id = id; self.name = name; self.gatewayURL = gatewayURL; self.webURL = webURL
        self.sshHost = sshHost; self.sshPort = sshPort; self.sshUser = sshUser
        self.sshAuthKind = sshAuthKind; self.refreshInterval = refreshInterval
    }

    public var isInsecure: Bool {
        [gatewayURL, webURL].compactMap { $0 }.contains { URLComponents(string: $0)?.scheme?.lowercased() == "http" }
    }

    public var webPort: Int {
        let components = webURL.flatMap { URLComponents(string: $0) }
        return components?.port ?? (components?.scheme?.lowercased() == "https" ? 443 : 80)
    }

    public func validate() -> [String] {
        var errors: [String] = []
        if !Self.validURL(gatewayURL) { errors.append("网关地址无效，请输入完整的 http 或 https 地址，且不要包含凭据、查询参数或片段。") }
        if let webURL, !webURL.isEmpty, !Self.validURL(webURL) { errors.append("Web 地址无效，请输入完整的 http 或 https 地址，且不要包含凭据、查询参数或片段。") }
        if !(1...65535).contains(sshPort) { errors.append("SSH 端口须在 1 到 65535 之间。") }
        if !refreshInterval.isFinite || refreshInterval <= 0 { errors.append("刷新间隔须大于零。") }
        return errors
    }

    private static func validURL(_ string: String) -> Bool {
        guard !string.contains(where: { $0.isWhitespace }),
              let components = URLComponents(string: string), components.url != nil,
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return false }
        return components.port.map { (1...65535).contains($0) } ?? true
    }
}
