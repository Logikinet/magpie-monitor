import Foundation

public enum SecretField: String, CaseIterable, Sendable {
    case gatewayKey, runtimeKey, sshPrivateKey, sshPassphrase, sshPassword, hostKey

    public func account(profileID: UUID) -> String {
        "magpie-ios.\(profileID.uuidString).\(rawValue)"
    }
}

public protocol SecretStore: Sendable {
    func get(account: String) async throws -> String?
    func set(_ value: String, account: String) async throws
    func delete(account: String) async throws
}

public actor InMemorySecretStore: SecretStore {
    private var values: [String: String] = [:]
    public init() {}
    public func get(account: String) -> String? { values[account] }
    public func set(_ value: String, account: String) { values[account] = value }
    public func delete(account: String) { values[account] = nil }
}
