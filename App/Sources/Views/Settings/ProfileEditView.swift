import SwiftUI
import MagpieKit

struct ProfileEditView: View {
    let initial: ProfileConfig?
    let onSave: (ProfileConfig, [SecretField: String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var gatewayURL = ""
    @State private var webURL = ""
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
                Section("基本信息") {
                    TextField("名称", text: $name)
                    TextField("网关 URL", text: $gatewayURL).textInputAutocapitalization(.never).keyboardType(.URL)
                    SecureField("网关密钥", text: $gatewayKey)
                    TextField("Web GUI URL", text: $webURL).textInputAutocapitalization(.never).keyboardType(.URL)
                    SecureField("Runtime 密钥", text: $runtimeKey)
                    if isHTTP { Label("HTTP 连接未加密，仅建议在 Tailscale 等私有网络内使用。", systemImage: "lock.open.fill").foregroundStyle(.orange).font(.footnote) }
                    Text("非本机访问需在 magpie 设置开启 Share on local network").font(.footnote).foregroundStyle(.secondary)
                }
                Section("SSH") {
                    TextField("主机", text: $sshHost).textInputAutocapitalization(.never)
                    TextField("端口", text: $sshPort).keyboardType(.numberPad)
                    TextField("用户名", text: $sshUser).textInputAutocapitalization(.never)
                    Picker("认证方式", selection: $authKind) { Text("私钥").tag(SSHAuthKind.privateKey); Text("密码").tag(SSHAuthKind.password) }
                    if authKind == .privateKey {
                        TextField("私钥（PEM / OpenSSH）", text: $privateKey, axis: .vertical).lineLimit(5...10).textInputAutocapitalization(.never).font(.system(.body, design: .monospaced))
                        SecureField("私钥口令（可选）", text: $passphrase)
                        Text("支持 ed25519 或 RSA 私钥。私钥仅保存在设备钥匙串中。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else { SecureField("SSH 密码", text: $password) }
                }
                if !errors.isEmpty { Section { ForEach(errors, id: \.self) { Text($0).foregroundStyle(.red).font(.footnote) } } }
            }
            .navigationTitle(initial == nil ? "添加服务器" : "编辑服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .onAppear(perform: populate)
        }
    }
    private var isHTTP: Bool { gatewayURL.lowercased().hasPrefix("http://") || webURL.lowercased().hasPrefix("http://") }
    private func populate() {
        guard let p = initial else { gatewayURL = "http://devbox.example.ts.net:3425"; return }
        name = p.name; gatewayURL = p.gatewayURL; webURL = p.webURL ?? ""; sshHost = p.sshHost
        sshPort = String(p.sshPort); sshUser = p.sshUser; authKind = p.sshAuthKind
    }
    private func save() {
        let port = Int(sshPort) ?? 0
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errors = ["请输入服务器名称。"]; return }
        let profile = ProfileConfig(id: initial?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), gatewayURL: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines), webURL: webURL.isEmpty ? nil : webURL.trimmingCharacters(in: .whitespacesAndNewlines), sshHost: sshHost, sshPort: port, sshUser: sshUser, sshAuthKind: authKind, refreshInterval: initial?.refreshInterval ?? 20)
        errors = profile.validate()
        guard errors.isEmpty else { return }
        var secrets: [SecretField: String] = [:]
        if !gatewayKey.isEmpty { secrets[.gatewayKey] = gatewayKey }
        if !runtimeKey.isEmpty { secrets[.runtimeKey] = runtimeKey }
        if !privateKey.isEmpty { secrets[.sshPrivateKey] = privateKey }
        if !passphrase.isEmpty { secrets[.sshPassphrase] = passphrase }
        if !password.isEmpty { secrets[.sshPassword] = password }
        onSave(profile, secrets); dismiss()
    }
}
