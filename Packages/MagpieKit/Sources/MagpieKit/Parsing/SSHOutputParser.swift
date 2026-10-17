import Foundation

public struct Port: Equatable {
    public let address: String
    public let port: Int
    public let processName: String?
}
public struct Container: Equatable {
    public let id: String; public let name: String; public let image: String
    public let state: String; public let status: String; public let ports: String
    public var isRunning: Bool { state.caseInsensitiveCompare("running") == .orderedSame }
}
public struct ServiceUnit: Equatable {
    public let name: String; public let load: String; public let active: String
    public let sub: String; public let description: String
}
public struct RemoteProcess: Equatable {
    public let pid: Int; public let ppid: Int; public let cpu: Double; public let memory: Double
    public let command: String; public let arguments: String
}
public struct TmuxSession: Equatable {
    public let name: String; public let windows: Int; public let attached: Int
}

public enum SSHOutputParser {
    public static func parsePorts(_ output: String) -> [Port] {
        output.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard columns.count >= 4 else { return nil }
            let local = columns[3]
            guard let (address, port) = endpoint(local) else { return nil }
            let procText = columns.first(where: { $0.contains("users:(") }) ?? columns.first(where: { $0.contains("/") })
            let process = procText.flatMap { text -> String? in
                if let start = text.range(of: "((\""), let end = text[start.upperBound...].firstIndex(of: "\"") { return String(text[start.upperBound..<end]) }
                if let slash = text.lastIndex(of: "/") { return String(text[text.index(after: slash)...].split(separator: ",").first ?? "") }
                return nil
            }
            return Port(address: address, port: port, processName: process)
        }
    }

    public static func parseDockerPS(_ output: String) -> [Container] {
        output.split(whereSeparator: \.isNewline).compactMap { raw in
            let fields = raw.components(separatedBy: "\t")
            guard fields.count >= 2, !fields[0].isEmpty, !fields[1].isEmpty else { return nil }
            return Container(id: fields[0], name: fields[1], image: fields[safe: 2] ?? "", state: fields[safe: 3] ?? "", status: fields[safe: 4] ?? "", ports: fields[safe: 5] ?? "")
        }
    }

    public static func parseSystemdUnits(_ output: String) -> [ServiceUnit] {
        output.split(whereSeparator: \.isNewline).compactMap { raw in
            let fields = raw.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 4 else { return nil }
            return ServiceUnit(name: fields[0], load: fields[1], active: fields[2], sub: fields[3], description: fields.dropFirst(4).joined(separator: " "))
        }
    }

    public static func parseProcesses(_ output: String) -> [RemoteProcess] {
        output.split(whereSeparator: \.isNewline).compactMap { raw in
            let fields = raw.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 6, let pid = Int(fields[0]), let ppid = Int(fields[1]), let cpu = Double(fields[2]), let memory = Double(fields[3]) else { return nil }
            return RemoteProcess(pid: pid, ppid: ppid, cpu: cpu, memory: memory, command: fields[4], arguments: fields.dropFirst(5).joined(separator: " "))
        }
    }

    public static func parseTmuxSessions(_ output: String) -> [TmuxSession] {
        output.split(whereSeparator: \.isNewline).compactMap { raw in
            let fields = raw.components(separatedBy: "\t")
            guard fields.count >= 3, !fields[0].isEmpty, let windows = Int(fields[1]), let attached = Int(fields[2]) else { return nil }
            return TmuxSession(name: fields[0], windows: windows, attached: attached)
        }
    }

    private static func endpoint(_ value: String) -> (String, Int)? {
        let host: Substring; let portText: Substring
        if value.first == "[", let close = value.firstIndex(of: "]"), value.index(after: close) < value.endIndex {
            host = value[value.index(after: value.startIndex)..<close]
            guard value[value.index(after: close)] == ":" else { return nil }
            portText = value[value.index(value.index(after: close), offsetBy: 1)...]
        } else if let colon = value.lastIndex(of: ":") {
            host = value[..<colon]; portText = value[value.index(after: colon)...]
        } else { return nil }
        guard let port = Int(portText), (0...65535).contains(port) else { return nil }
        return (host.isEmpty || host == "*" ? "0.0.0.0" : String(host), port)
    }
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String? { indices.contains(index) ? self[index] : nil }
}

