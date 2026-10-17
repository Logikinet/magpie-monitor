import Foundation
import Observation
import MagpieKit
import SSHKit

@MainActor @Observable
final class AppState {
    private(set) var profiles: [ProfileConfig] = []
    private(set) var selectedID: UUID?
    var isMockMode: Bool { didSet { UserDefaults.standard.set(isMockMode, forKey: "isMockMode") } }
    var isActive = true
    private(set) var persistenceError: String?
    let secretStore = KeychainSecretStore()
    private let fileURL: URL

    var currentProfile: ProfileConfig? { profiles.first { $0.id == selectedID } }
    var refreshInterval: TimeInterval {
        let interval = currentProfile?.refreshInterval ?? 20
        return interval.isFinite ? max(1, interval) : 20
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        fileURL = support.appendingPathComponent("profiles.json")
        isMockMode = UserDefaults.standard.bool(forKey: "isMockMode")
        load()
        if profiles.isEmpty, UserDefaults.standard.object(forKey: "isMockMode") == nil { isMockMode = true }
    }

    func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedID = id
        save()
    }
    func saveProfile(_ profile: ProfileConfig) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile } else { profiles.append(profile) }
        if selectedID == nil { selectedID = profile.id }
        save()
    }
    func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if selectedID == id { selectedID = profiles.first?.id }
        save()
        Task {
            do { for field in SecretField.allCases { try await secretStore.delete(account: field.account(profileID: id)) } } catch {
                persistenceError = ErrorMessages.chinese(for: error)
            }
        }
    }

    func makeGatewayClient() -> GatewayClient? {
        if isMockMode {
            guard let url = URL(string: "https://example.ts.net") else { return nil }
            return GatewayClient(baseURL: url, key: nil, transport: makeTransport())
        }
        guard let profile = currentProfile, let url = URL(string: profile.gatewayURL) else { return nil }
        let transport: any HTTPTransport = makeTransport()
        let account = SecretField.gatewayKey.account(profileID: profile.id)
        let key = try? secretStore.read(account: account)
        return GatewayClient(baseURL: url, key: key, transport: transport)
    }

    func makeCollectorClient() -> CollectorClient? {
        if isMockMode {
            guard let transport = try? MockTransport.collectorFixtures(), let url = URL(string: "https://example.ts.net") else { return nil }
            return CollectorClient(baseURL: url, key: nil, transport: transport)
        }
        guard let profile = currentProfile, let raw = profile.collectorURL, let url = URL(string: raw) else { return nil }
        let key = try? secretStore.read(account: SecretField.collectorKey.account(profileID: profile.id))
        return CollectorClient(baseURL: url, key: key, transport: LiveTransport())
    }

    func makeWebClient() -> WebClient? {
        guard let profile = currentProfile, let rawURL = profile.webURL, let url = URL(string: rawURL) else { return nil }
        let account = SecretField.runtimeKey.account(profileID: profile.id)
        let provider = secretStore
        let key = try? secretStore.read(account: account)
        return WebClient(baseURL: url, runtimeKey: key, transport: makeTransport(), port: profile.webPort) {
            try? await provider.get(account: account)
        }
    }

    func makeOverviewSSHRunner() async throws -> any SSHRunning {
        try Task.checkCancellation()
        if isMockMode { return MockSSHRunner() }
        guard let profile = currentProfile else { throw MagpieError.sshFailed(String(localized: "请先选择服务器配置。")) }
        let read: (SecretField) -> String? = { [secretStore] field in
            try? secretStore.read(account: field.account(profileID: profile.id))
        }
        let auth: SSHConfig.Authentication
        switch profile.sshAuthKind {
        case .privateKey:
            guard let key = read(.sshPrivateKey), !key.isEmpty else { throw MagpieError.sshAuthFailed }
            auth = .privateKey(pem: key, passphrase: read(.sshPassphrase))
        case .password:
            guard let password = read(.sshPassword), !password.isEmpty else { throw MagpieError.sshAuthFailed }
            auth = .password(password)
        }
        let connection = SSHConnection()
        let pin = read(.hostKey)
        let fingerprint = try await connection.connect(
            config: SSHConfig(host: profile.sshHost, port: profile.sshPort, user: profile.sshUser, auth: auth),
            pinnedFingerprint: pin
        )
        if pin == nil {
            do { try await secretStore.set(fingerprint, account: SecretField.hostKey.account(profileID: profile.id)) } catch {
                await connection.disconnect()
                persistenceError = ErrorMessages.chinese(for: error)
                throw MagpieError.sshFailed(String(localized: "无法保存 SSH 主机指纹，请检查设备钥匙串后重试。"))
            }
        }
        return connection
    }

    private func makeTransport() -> any HTTPTransport {
        guard isMockMode else { return LiveTransport() }
        let names = ["hello", "usage", "ledger", "quotas", "quota_cards", "route", "concurrency", "trace"]
        var fixtures: [String: Data] = [:]
        for name in names {
            if let data = try? MockFixtures.data(named: name) {
                fixtures["/" + (name == "hello" ? "api/hello" : "v1/magpie/" + name.replacingOccurrences(of: "_", with: "/"))] = data
            }
        }
        // Explicit endpoint routing to the supplied safe fixtures.
        fixtures["/v1/magpie/usage"] = try? MockFixtures.data(named: "usage")
        fixtures["/v1/magpie/usage/requests"] = try? MockFixtures.data(named: "ledger")
        fixtures["/v1/magpie/quotas"] = try? MockFixtures.data(named: "quotas")
        fixtures["/v1/magpie/quotas/cards"] = try? MockFixtures.data(named: "quota_cards")
        fixtures["/v1/magpie/route"] = try? MockFixtures.data(named: "route")
        fixtures["/v1/magpie/concurrency"] = try? MockFixtures.data(named: "concurrency")
        fixtures["/api/gateway/trace"] = try? MockFixtures.data(named: "trace")
        return MockTransport(fixtures: fixtures.compactMapValues { $0 })
    }
    private func load() {
        var store = ProfileStore(fileURL: fileURL)
        do {
            try store.load()
            profiles = store.profiles
            selectedID = store.selectedID
        } catch { persistenceError = String(localized: "无法读取服务器配置。") }
    }
    private func save() {
        var store = ProfileStore(fileURL: fileURL)
        for profile in profiles { store.add(profile) }
        if let selectedID { store.select(id: selectedID) }
        do {
            try store.save()
            persistenceError = nil
        } catch { persistenceError = String(localized: "无法保存服务器配置。") }
    }
}
