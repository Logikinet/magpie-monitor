import XCTest
@testable import MagpieKit

final class SSHParsingTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testPorts() throws {
        let ports = SSHOutputParser.parsePorts(try fixture("ss"))
        XCTAssertEqual(ports.count, 2)
        XCTAssertEqual(ports[0].port, 22)
        XCTAssertEqual(ports[0].processName, "sshd")
        XCTAssertEqual(ports[1].processName, "postgres")
    }

    func testDockerPSAndOddLines() throws {
        let containers = SSHOutputParser.parseDockerPS(try fixture("docker_ps"))
        XCTAssertEqual(containers.count, 3)
        XCTAssertTrue(containers[0].isRunning)
        XCTAssertEqual(containers[2].name, "short")
    }

    func testSystemdUnits() throws {
        let units = SSHOutputParser.parseSystemdUnits(try fixture("systemctl"))
        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units[0].description, "OpenBSD Secure Shell server")
    }

    func testProcesses() throws {
        let processes = SSHOutputParser.parseProcesses(try fixture("ps"))
        XCTAssertEqual(processes.count, 2)
        XCTAssertEqual(processes[1].arguments, "sshd: example [listener]")
    }

    func testMockCommandFixturesAreParseable() throws {
        let ports = SSHOutputParser.parsePorts(String(decoding: try MockFixtures.data(named: "ss.txt"), as: UTF8.self))
        let containers = SSHOutputParser.parseDockerPS(String(decoding: try MockFixtures.data(named: "docker_ps.txt"), as: UTF8.self))
        let units = SSHOutputParser.parseSystemdUnits(String(decoding: try MockFixtures.data(named: "systemctl.txt"), as: UTF8.self))
        let processes = SSHOutputParser.parseProcesses(String(decoding: try MockFixtures.data(named: "ps.txt"), as: UTF8.self))
        let sessions = SSHOutputParser.parseTmuxSessions(String(decoding: try MockFixtures.data(named: "tmux_ls.txt"), as: UTF8.self))

        XCTAssertEqual(ports.count, 4)
        XCTAssertEqual(containers.count, 4)
        XCTAssertEqual(units.count, 5)
        XCTAssertEqual(processes.count, 6)
        XCTAssertEqual(sessions.count, 3)
    }

    func testTmuxSessions() throws {
        let sessions = SSHOutputParser.parseTmuxSessions(try fixture("tmux_ls"))
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].attached, 1)
    }

    func testTmuxCommandUsesLiteralTabSeparators() {
        XCTAssertTrue(SSHCommands.tmuxSessions.contains("#{session_name}\t#{session_windows}\t#{session_attached}"))
        XCTAssertFalse(SSHCommands.tmuxSessions.contains("\\t"))
        let sessions = SSHOutputParser.parseTmuxSessions("demo\t2\t1\ninvalid\n")
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.name, "demo")
        XCTAssertEqual(sessions.first?.windows, 2)
    }

    func testCommandBuildersQuoteAndRejectUnsafeNames() throws {
        XCTAssertEqual(try SSHCommands.startDockerContainer("safe_name-1"), "docker start 'safe_name-1'")
        XCTAssertEqual(try SSHCommands.stopSystemdUnit("demo.service", useSudo: true), "sudo -n systemctl stop 'demo.service'")
        XCTAssertThrowsError(try SSHCommands.startDockerContainer("foo; rm -rf /"))
        XCTAssertThrowsError(try SSHCommands.stopSystemdUnit("$(bad)"))
    }
}
