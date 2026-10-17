import SwiftUI
import MagpieKit

struct ProfileEditView: View {
    let initial: ProfileConfig?
    let onSave: (ProfileConfig, [SecretField: String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var gatewayURL = ""
    @State private var webURL = ""
    @State private var collectorURL = ""
    @State private var collectorKey = ""
    @State private var sshHost = ""
    @State private var sshPort = "22"
    @State private var sshUser = ""
    @State private var authKind: SSHAuthKind = .privateKey
    @State private var gatewayKey = ""
    @State private var runtimeKey = ""
    @State private var privateKey = ""
    @State private var passphrase = ""
    @State private var password = ""
    @State private var errors: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "基本信息")) {
                    TextField(String(localized: "名称"), text: $name)
                    TextField(String(localized: "网关 URL"), text: $gatewayURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField(String(localized: "网关密钥"), text: $gatewayKey)
                    TextField("Web GUI URL", text: $webURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField(String(localized: "Runtime 密钥"), text: $runtimeKey)
                    if isHTTP {
                        Label(String(localized: "HTTP 连接未加密，仅建议在 Tailscale 等私有网络内使用。"), systemImage: "lock.open.fill").foregroundStyle(.orange).font(.footnote)
                    }
                    Text(String(localized: "非本机访问需在 magpie 设置开启 Share on local network")).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Collector") {
                    TextField("Collector URL", text: $collectorURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField(String(localized: "Collector 密钥"), text: $collectorKey)
                    if collectorURL.lowercased().hasPrefix("http://") {
                        Label(String(localized: "HTTP 连接未加密，仅建议在 Tailscale 等私有网络内使用。"), systemImage: "lock.open.fill").font(.footnote).foregroundStyle(.orange)
                    }
                }
                Section("SSH") {
                    TextField(String(localized: "主机"), text: $sshHost).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(String(localized: "端口"), text: $sshPort).keyboardType(.numberPad)
                    TextField(String(localized: "用户名"), text: $sshUser).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker(String(localized: "认证方式"), selection: $authKind) {
                        Text(String(localized: "私钥")).tag(SSHAuthKind.privateKey)
                        Text(String(localized: "密码")).tag(SSHAuthKind.password)
                    }
                    if authKind == .privateKey {
                        TextField(String(localized: "私钥（PEM / OpenSSH）"), text: $privateKey, axis: .vertical).lineLimit(5...10).textInputAutocapitalization(
                            .never
                        ).autocorrectionDisabled().font(.system(.body, design: .monospaced))
                        SecureField(String(localized: "私钥口令（可选）"), text: $passphrase)
                        Text(String(localized: "支持 ed25519 或 RSA 私钥。私钥仅保存在设备钥匙串中。"))
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        SecureField(String(localized: "SSH 密码"), text: $password)
                    }
                }
                if !errors.isEmpty { Section { ForEach(errors, id: \.self) { Text($0).foregroundStyle(.red).font(.footnote) } } }
            }
            .navigationTitle(initial == nil ? String(localized: "添加服务器") : String(localized: "编辑服务器"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "保存")) { save() } }
            }
            .onAppear(perform: populate)
        }
    }
    private var isHTTP: Bool { gatewayURL.lowercased().hasPrefix("http://") || webURL.lowercased().hasPrefix("http://") }
    private func populate() {
        guard let p = initial else {
            gatewayURL = "http://devbox.example.ts.net:3425"
            return
        }
        name = p.name
        gatewayURL = p.gatewayURL
        webURL = p.webURL ?? ""
        collectorURL = p.collectorURL ?? ""
        sshHost = p.sshHost
        sshPort = String(p.sshPort)
        sshUser = p.sshUser
        authKind = p.sshAuthKind
    }
    private func save() {
        let port = Int(sshPort) ?? 0
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errors = [String(localized: "请输入服务器名称。")]
            return
        }
        let profile = ProfileConfig(
            id: initial?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            gatewayURL: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines),
            webURL: webURL.isEmpty ? nil : webURL.trimmingCharacters(in: .whitespacesAndNewlines), collectorURL: collectorURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : collectorURL.trimmingCharacters(in: .whitespacesAndNewlines), sshHost: sshHost, sshPort: port,
            sshUser: sshUser, sshAuthKind: authKind, refreshInterval: initial?.refreshInterval ?? 20)
        errors = profile.validate().map { NSLocalizedString($0, comment: "Profile validation") }
        guard errors.isEmpty else { return }
        var secrets: [SecretField: String] = [:]
        if !collectorKey.isEmpty { secrets[.collectorKey] = collectorKey }
        if !gatewayKey.isEmpty { secrets[.gatewayKey] = gatewayKey }
        if !runtimeKey.isEmpty { secrets[.runtimeKey] = runtimeKey }
        if !privateKey.isEmpty { secrets[.sshPrivateKey] = privateKey }
        if !passphrase.isEmpty { secrets[.sshPassphrase] = passphrase }
        if !password.isEmpty { secrets[.sshPassword] = password }
        onSave(profile, secrets)
        dismiss()
    }
}
