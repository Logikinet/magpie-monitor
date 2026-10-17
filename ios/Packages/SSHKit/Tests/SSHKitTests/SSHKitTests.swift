import XCTest
import MagpieKit
import NIOEmbedded
import NIOSSH
@testable import SSHKit

final class SSHKitTests: XCTestCase {
    // A synthetic public key, with no corresponding stored private key.
    private let publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"
    private let fingerprint = "SHA256:ZkAslGjFiUHdGf/WUL8rQvkib4PTvQatUV0OUQSncCA"

    func testOpenSSHWireFingerprintAndTOFU() throws {
        let key = try NIOSSHPublicKey(openSSHPublicKey: publicKey)
        for pin in [nil, Optional(fingerprint)] {
            let loop = EmbeddedEventLoop()
            let promise = loop.makePromise(of: Void.self)
            let validator = HostKeyValidator(pin: pin)
            validator.validateHostKey(hostKey: key, validationCompletePromise: promise)
            loop.run()
            XCTAssertNoThrow(try promise.futureResult.wait())
            XCTAssertEqual(validator.fingerprint, fingerprint)
            XCTAssertFalse(validator.changed)
        }
    }

    func testChangedHostKeyIsRejected() throws {
        let loop = EmbeddedEventLoop()
        let promise = loop.makePromise(of: Void.self)
        let validator = HostKeyValidator(pin: "SHA256:different")
        validator.validateHostKey(
            hostKey: try NIOSSHPublicKey(openSSHPublicKey: publicKey),
            validationCompletePromise: promise
        )
        loop.run()
        XCTAssertThrowsError(try promise.futureResult.wait()) {
            XCTAssertEqual($0 as? MagpieError, .sshHostKeyChanged)
        }
        XCTAssertTrue(validator.changed)
    }

    func testMockCommandsReturnParseableFixtures() async throws {
        let runner: any SSHRunning = MockSSHRunner()
        let ports = try await runner.run(SSHCommands.ports, idempotent: true)
        let containers = try await runner.run(SSHCommands.dockerPS, idempotent: true)
        let units = try await runner.run(SSHCommands.systemdUnits, idempotent: true)
        let processes = try await runner.run(SSHCommands.processes, idempotent: true)
        let sessions = try await runner.run(SSHCommands.tmuxSessions, idempotent: true)
        XCTAssertFalse(SSHOutputParser.parsePorts(ports).isEmpty)
        XCTAssertFalse(SSHOutputParser.parseDockerPS(containers).isEmpty)
        XCTAssertFalse(SSHOutputParser.parseSystemdUnits(units).isEmpty)
        XCTAssertFalse(SSHOutputParser.parseProcesses(processes).isEmpty)
        XCTAssertFalse(SSHOutputParser.parseTmuxSessions(sessions).isEmpty)
        do {
            _ = try await runner.run("docker stop example", idempotent: false)
            XCTFail("模拟模式应拒绝未支持的命令")
        } catch { XCTAssertNotNil(error as? MagpieError) }
    }

    func testDisconnectedConnectionDoesNotRunCommands() async {
        let connection = SSHConnection()
        do {
            _ = try await connection.run("true", idempotent: true)
            XCTFail("未连接时应失败")
        } catch { XCTAssertNotNil(error as? MagpieError) }
        await connection.disconnect()
        await connection.disconnect()
    }

    func testInvalidPrivateKeyFailsBeforeNetworkConnection() async {
        let connection = SSHConnection()
        do {
            try await connection.connect(config: SSHConfig(
                host: "example.ts.net", user: "example",
                auth: .privateKey(pem: "invalid", passphrase: nil)
            ))
            XCTFail("无效私钥应失败")
        } catch { XCTAssertEqual(error as? MagpieError, .sshAuthFailed) }
    }
}
