import Foundation

public enum SSHCommands {
    public static let ports = "ss -tlnpH 2>/dev/null || netstat -tlnp 2>/dev/null"
    public static let dockerPS = "docker ps -a --format '{{.ID}}\\t{{.Names}}\\t{{.Image}}\\t{{.State}}\\t{{.Status}}\\t{{.Ports}}'"
    public static let systemdUnits = "systemctl list-units --type=service --all --no-pager --plain --no-legend"
    public static let processes = "ps -eo pid,ppid,pcpu,pmem,comm,args --no-headers"
    public static let tmuxSessions = "tmux list-sessions -F '#{session_name}\\t#{session_windows}\\t#{session_attached}'"

    public static func startDockerContainer(_ name: String) throws -> String { try dockerAction("start", name) }
    public static func stopDockerContainer(_ name: String) throws -> String { try dockerAction("stop", name) }
    public static func startSystemdUnit(_ name: String, useSudo: Bool = false) throws -> String { try systemdAction("start", name, useSudo: useSudo) }
    public static func stopSystemdUnit(_ name: String, useSudo: Bool = false) throws -> String { try systemdAction("stop", name, useSudo: useSudo) }

    private static func dockerAction(_ action: String, _ name: String) throws -> String {
        "docker \(action) \(try quotedName(name))"
    }
    private static func systemdAction(_ action: String, _ name: String, useSudo: Bool) throws -> String {
        "\(useSudo ? "sudo -n " : "")systemctl \(action) \(try quotedName(name))"
    }
    private static func quotedName(_ name: String) throws -> String {
        guard !name.isEmpty, name.range(of: "^[A-Za-z0-9_.@:-]+$", options: .regularExpression) != nil else {
            throw SSHCommandError.invalidName
        }
        return "'\(name)'"
    }
}

public enum SSHCommandError: Error, Equatable { case invalidName }
