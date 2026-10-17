public protocol SSHRunning: Sendable {
    func run(_ command: String, idempotent: Bool) async throws -> String
    func disconnect() async
}

extension SSHRunning {
    public func run(_ command: String) async throws -> String {
        try await run(command, idempotent: false)
    }
}
