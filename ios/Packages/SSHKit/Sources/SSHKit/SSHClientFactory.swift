import Foundation
@preconcurrency import Citadel
import Crypto
import NIOCore
@preconcurrency import NIOSSH
import MagpieKit

/// All Citadel authentication and host-key API usage is isolated here.
enum SSHClientFactory {
    static func connect(config: SSHConfig, pin: String?) async throws -> (SSHClient, String) {
        guard !config.host.isEmpty, !config.user.isEmpty, (1...65535).contains(config.port) else {
            throw MagpieError.sshFailed("请检查 SSH 地址、端口和用户名。")
        }
        let authentication: SSHAuthenticationMethod
        do {
            switch config.auth {
            case .password(let password):
                authentication = .passwordBased(username: config.user, password: password)
            case .privateKey(let pem, let passphrase):
                let key = pem.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\r\n", with: "\n")
                let decryptionKey = passphrase.map { Data($0.utf8) }
                let type = try SSHKeyDetection.detectPrivateKeyType(from: key)
                switch type {
                case .ed25519:
                    authentication = .ed25519(username: config.user, privateKey:
                        try Curve25519.Signing.PrivateKey(sshEd25519: key, decryptionKey: decryptionKey))
                case .rsa:
                    authentication = .rsa(username: config.user, privateKey:
                        try Insecure.RSA.PrivateKey(sshRsa: key, decryptionKey: decryptionKey))
                default: throw MagpieError.sshAuthFailed
                }
            }
        } catch { throw MagpieError.sshAuthFailed }

        let validator = HostKeyValidator(pin: pin)
        do {
            let client = try await SSHClient.connect(
                host: config.host, port: config.port, authenticationMethod: authentication,
                hostKeyValidator: .custom(validator), reconnect: .never
            )
            guard let fingerprint = validator.fingerprint else {
                try? await client.close()
                throw MagpieError.sshFailed("无法读取 SSH 主机指纹。")
            }
            if Task.isCancelled {
                try? await client.close()
                throw CancellationError()
            }
            return (client, fingerprint)
        } catch {
            if validator.changed { throw MagpieError.sshHostKeyChanged }
            throw map(error)
        }
    }

    static func map(_ error: Error) -> MagpieError {
        if let error = error as? MagpieError { return error }
        if error is CancellationError || Task.isCancelled { return .cancelled }
        if error is AuthenticationFailed { return .sshAuthFailed }
        if let error = error as? SSHClientError {
            switch error {
            case .allAuthenticationOptionsFailed, .unsupportedPasswordAuthentication,
                 .unsupportedPrivateKeyAuthentication, .unsupportedHostBasedAuthentication:
                return .sshAuthFailed
            default: break
            }
        }
        if let error = error as? CitadelError, case .unauthorized = error { return .sshAuthFailed }
        // Never include upstream descriptions, which may contain credentials or commands.
        return .sshFailed("SSH 连接或命令执行失败。")
    }
}

/// NIOSSH invokes this delegate on its event loop; reads occur on the connection actor.
final class HostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let pin: String?
    private var observed: String?
    private var mismatch = false

    init(pin: String?) { self.pin = pin }

    var fingerprint: String? { lock.withLock { observed } }
    var changed: Bool { lock.withLock { mismatch } }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        // Hash the complete RFC 4253 wire blob, not the raw algorithm-specific key.
        let fields = String(openSSHPublicKey: hostKey).split(separator: " ")
        guard fields.count >= 2, let blob = Data(base64Encoded: String(fields[1])) else {
            validationCompletePromise.fail(MagpieError.sshFailed("无法读取 SSH 主机指纹。"))
            return
        }
        let fingerprint = "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let rejected = lock.withLock {
            observed = fingerprint
            mismatch = pin.map { $0 != fingerprint } ?? false
            return mismatch
        }
        if rejected { validationCompletePromise.fail(MagpieError.sshHostKeyChanged) }
        else { validationCompletePromise.succeed(()) }
    }
}
