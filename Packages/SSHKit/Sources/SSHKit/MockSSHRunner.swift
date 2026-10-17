import Foundation
import MagpieKit

/// Reads the same sanitized fixtures as MagpieKit's parser tests; never connects.
public struct MockSSHRunner: SSHRunning {
    public init() {}

    public func run(_ command: String, idempotent: Bool = false) async throws -> String {
        try Task.checkCancellation()
        let fixture: String
        switch command {
        case let value where value.hasPrefix("ss "): fixture = "ss"
        case let value where value.hasPrefix("docker ps"): fixture = "docker_ps"
        case let value where value.hasPrefix("systemctl list-units"): fixture = "systemctl"
        case let value where value.hasPrefix("ps "): fixture = "ps"
        case let value where value.hasPrefix("tmux ls"),
             let value where value.hasPrefix("tmux list-sessions"): fixture = "tmux_ls"
        default: throw MagpieError.sshFailed("模拟模式不支持此命令。")
        }
        guard let url = MockFixtures.bundle.url(
            forResource: fixture, withExtension: "txt", subdirectory: "MockData"
        ) else { throw MagpieError.sshFailed("找不到模拟 SSH 数据。") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func disconnect() async {}
}
