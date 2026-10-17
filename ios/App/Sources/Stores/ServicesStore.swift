import Foundation
import Observation
import MagpieKit
import SSHKit

enum ServicesCategory: String, CaseIterable, Identifiable, Hashable {
    case containers
    var title: String { self == .containers ? String(localized: "容器") : "systemd" }
    case systemd = "systemd"
    var id: String { rawValue }
}

enum ServiceAction: String, CaseIterable, Identifiable, Hashable {
    var title: String {
        switch self {
        case .start: String(localized: "启动")
        case .stop: String(localized: "停止")
        case .restart: String(localized: "重启")
        }
    }
    case start
    case stop
    case restart
    var id: String { rawValue }
}

struct ServiceEntry: Identifiable, Equatable {
    let id: String
    let category: ServicesCategory
    let name: String
    let detail: String
    let state: String

    var status: (kind: DS.StatusKind, title: String) {
        let value = state.lowercased()
        if ["running", "active"].contains(value) { return (.ok, String(localized: "运行中")) }
        if ["restarting", "activating", "deactivating"].contains(value) { return (.warning, String(localized: "处理中")) }
        if ["exited", "dead", "inactive"].contains(value) { return (.neutral, String(localized: "已停止")) }
        if ["failed"].contains(value) { return (.error, String(localized: "失败")) }
        return (.neutral, state.isEmpty ? String(localized: "未知") : state)
    }
}

struct ServiceOperation: Identifiable {
    let entry: ServiceEntry
    let action: ServiceAction
    let command: String
    var id: String { "\(entry.id):\(action.id)" }
}

@MainActor @Observable
final class ServicesStore {
    private(set) var collectorServices: [CollectorRecord]?
    private(set) var collectorHostname: String?
    private(set) var collectorError: String?
    private(set) var containers: [Container] = []
    private(set) var units: [ServiceUnit] = []
    private(set) var containersError: String?
    private(set) var unitsError: String?
    private(set) var isRefreshing = false
    private(set) var inFlightIDs: Set<String> = []
    private(set) var lastUpdated: Date?
    private(set) var error: String?
    private(set) var notice: String?
    private var mockStates: [String: String] = [:]
    private var sudoProfileID: UUID?
    var useSudo = false {
        didSet {
            guard let sudoProfileID else { return }
            UserDefaults.standard.set(useSudo, forKey: Self.sudoKey(profileID: sudoProfileID))
        }
    }

    func entries(for category: ServicesCategory) -> [ServiceEntry] {
        switch category {
        case .containers:
            containers.map { item in
                let id = "container:\(item.name)"
                return ServiceEntry(
                    id: id, category: .containers, name: item.name,
                    detail: [item.image, item.status, item.ports].filter { !$0.isEmpty }.joined(separator: " · "),
                    state: mockStates[id] ?? item.state)
            }
        case .systemd:
            units.map { item in
                let id = "unit:\(item.name)"
                return ServiceEntry(
                    id: id, category: .systemd, name: item.name,
                    detail: [item.sub, item.description].filter { !$0.isEmpty }.joined(separator: " · "),
                    state: mockStates[id] ?? item.active)
            }
        }
    }

    func loadPreference(appState: AppState) {
        let profileID = appState.currentProfile?.id
        guard profileID != sudoProfileID else { return }
        sudoProfileID = profileID
        useSudo = profileID.map { UserDefaults.standard.bool(forKey: Self.sudoKey(profileID: $0)) } ?? false
    }

    func command(for entry: ServiceEntry, action: ServiceAction) throws -> String {
        switch (entry.category, action) {
        case (.containers, .start): try SSHCommands.startDockerContainer(entry.name)
        case (.containers, .stop): try SSHCommands.stopDockerContainer(entry.name)
        case (.containers, .restart): try SSHCommands.restartDockerContainer(entry.name)
        case (.systemd, .start): try SSHCommands.startSystemdUnit(entry.name, useSudo: useSudo)
        case (.systemd, .stop): try SSHCommands.stopSystemdUnit(entry.name, useSudo: useSudo)
        case (.systemd, .restart): try SSHCommands.restartSystemdUnit(entry.name, useSudo: useSudo)
        }
    }

    func prepareOperation(for entry: ServiceEntry, action: ServiceAction) -> ServiceOperation? {
        do {
            return ServiceOperation(entry: entry, action: action, command: try command(for: entry, action: action))
        } catch {
            self.error = String(localized: "服务名称无法用于安全命令，请刷新列表后重试。")
            return nil
        }
    }

    func refresh(appState: AppState, useCollector: Bool = true) async {
        guard !isRefreshing else { return }
        loadPreference(appState: appState)
        isRefreshing = true
        defer { isRefreshing = false }
        if useCollector, let client = appState.makeCollectorClient() {
            do {
                let rows = try await client.services().records("services")
                let name = try? await client.sys().string("hostname")
                collectorHostname = name
                collectorServices = rows
                collectorError = nil
                lastUpdated = Date()
                return
            } catch { collectorError = message(for: error) }
        }
        collectorServices = nil
        collectorHostname = nil
        do {
            let runner = try await appState.makeOverviewSSHRunner()
            do {
                async let containerOutput = runner.run(SSHCommands.dockerPS, idempotent: true)
                async let unitOutput = runner.run(SSHCommands.systemdUnits, idempotent: true)
                let outputs = try await (containerOutput, unitOutput)
                containers = SSHOutputParser.parseDockerPS(outputs.0)
                units = SSHOutputParser.parseSystemdUnits(outputs.1)
                containersError = nil
                unitsError = nil
                error = nil
                lastUpdated = Date()
            } catch {
                let message = message(for: error)
                containersError = message
                unitsError = message
                self.error = message
            }
            await runner.disconnect()
        } catch {
            let message = message(for: error)
            containersError = message
            unitsError = message
            self.error = message
        }
    }

    func perform(_ operation: ServiceOperation, appState: AppState) async {
        guard !inFlightIDs.contains(operation.entry.id) else { return }
        inFlightIDs.insert(operation.entry.id)
        defer { inFlightIDs.remove(operation.entry.id) }
        error = nil
        notice = nil
        if appState.isMockMode {
            switch operation.action {
            case .start, .restart: mockStates[operation.entry.id] = operation.entry.category == .containers ? "running" : "active"
            case .stop: mockStates[operation.entry.id] = operation.entry.category == .containers ? "exited" : "inactive"
            }
            notice = String(format: String(localized: "模拟操作：未连接 SSH。\\n%@"), locale: Locale.current, String(describing: operation.command))
            await refresh(appState: appState)
            return
        }
        do {
            let runner = try await appState.makeOverviewSSHRunner()
            do {
                _ = try await runner.run(operation.command, idempotent: false)
                await runner.disconnect()
                await refresh(appState: appState)
            } catch {
                await runner.disconnect()
                self.error = message(for: error)
            }
        } catch {
            self.error = message(for: error)
        }
    }

    private static func sudoKey(profileID: UUID) -> String { "services.useSudo.\(profileID.uuidString)" }

    private func message(for error: Error) -> String {
        ErrorMessages.chinese(for: error)
    }
}
