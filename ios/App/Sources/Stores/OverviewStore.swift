import Foundation
import Observation
import MagpieKit
import SSHKit

struct OverviewQuota: Identifiable {
    let id: String
    let provider: String
    let window: String
    let used: Double
    let limit: Double
    let tokenUsage: TokenUsageValue?

    var tokenSubtitle: String? {
        guard let tokenUsage else { return nil }
        let count = TokenFormatter.compact(tokenUsage.count, locale: Locale(identifier: "zh_CN"))
        switch tokenUsage.source {
        case .window: return "已消耗 \(count) token"
        case .today: return "今日已消耗 \(count) token"
        case .sevenDays: return "近 7 天已消耗 \(count) token"
        }
    }
}

@MainActor @Observable
final class OverviewStore {
    private(set) var quotas: [OverviewQuota] = []
    private(set) var quotaError: String?
    private(set) var concurrency: Concurrency?
    private(set) var concurrencyError: String?
    private(set) var version: String?
    private(set) var gatewayError: String?
    private(set) var limit: [String: JSONValue]?
    private(set) var ports: [ListeningPort] = []
    private(set) var portsError: String?
    private(set) var containers: [Container] = []
    private(set) var containersError: String?
    private(set) var units: [ServiceUnit] = []
    private(set) var unitsError: String?
    private(set) var processes: [RemoteProcess] = []
    private(set) var processesError: String?
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false

    func refresh(appState: AppState) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let client = appState.makeGatewayClient()
        async let quotaResult: Result<QuotaList, Error> = fetch {
            guard let client else { throw MagpieError.network("missing client") }
            return try await client.quotas()
        }
        async let concurrencyResult: Result<Concurrency, Error> = fetch {
            guard let client else { throw MagpieError.network("missing client") }
            return try await client.concurrency()
        }
        async let helloResult: Result<GatewayHello, Error> = fetch {
            guard let client else { throw MagpieError.network("missing client") }
            return try await client.hello()
        }
        async let limitResult: Result<[String: JSONValue], Error> = fetch {
            guard let client else { throw MagpieError.network("missing client") }
            return try await client.limit()
        }

        do {
            let result = try await quotaResult.get()
            async let todayUsage: Result<UsageSummary, Error> = fetch {
                guard let client else { throw MagpieError.network("missing client") }
                return try await client.usage(period: "today")
            }
            async let weeklyUsage: Result<UsageSummary, Error> = fetch {
                guard let client else { throw MagpieError.network("missing client") }
                return try await client.usage(period: "7d")
            }
            let usages = (await todayUsage, await weeklyUsage)
            var items: [OverviewQuota] = []
            for quota in result.data.elements {
                let windows = [(quota.fiveHourWindow, "5 小时"), (quota.weeklyWindow, "每周")]
                for (span, title) in windows {
                    guard let span else { continue }
                    guard span.unlimited != true else { continue }
                    if let used = span.usedPercentage {
                        let providerID = quota.provider ?? ""
                        let periodUsage = title == "每周" ? (try? usages.1.get()) : (try? usages.0.get())
                        items.append(
                            OverviewQuota(
                                id: "\(providerID.isEmpty ? quota.name ?? "provider" : providerID)-\(title)",
                                provider: quota.name ?? quota.provider ?? "提供方", window: title, used: used, limit: 100,
                                tokenUsage: TokenUsage.value(
                                    window: span,
                                    provider: providerID,
                                    usage: periodUsage,
                                    approximateSource: title == "每周" ? .sevenDays : .today)))
                    }
                }
            }
            quotas = items
            quotaError = nil
        } catch { quotaError = message(for: error) }

        do {
            concurrency = try await concurrencyResult.get()
            concurrencyError = nil
        } catch { concurrencyError = message(for: error) }
        do {
            version = try await helloResult.get().version
            gatewayError = nil
        } catch { gatewayError = message(for: error) }
        if case .success(let value) = await limitResult { limit = value }

        do {
            let runner = try await appState.makeOverviewSSHRunner()
            async let portsResult = fetch { try SSHOutputParser.parsePorts(await runner.run(SSHCommands.ports, idempotent: true)) }
            async let containersResult = fetch {
                try SSHOutputParser.parseDockerPS(await runner.run(SSHCommands.dockerPS, idempotent: true))
            }
            async let unitsResult = fetch {
                try SSHOutputParser.parseSystemdUnits(await runner.run(SSHCommands.systemdUnits, idempotent: true))
            }
            async let processesResult = fetch {
                try SSHOutputParser.parseProcesses(await runner.run(SSHCommands.processes, idempotent: true))
            }
            do {
                ports = try await portsResult.get()
                portsError = nil
            } catch { portsError = message(for: error) }
            do {
                containers = try await containersResult.get()
                containersError = nil
            } catch { containersError = message(for: error) }
            do {
                units = try await unitsResult.get().sorted {
                    let firstPriority = $0.active != "inactive" || $0.name.localizedCaseInsensitiveContains("magpie")
                    let secondPriority = $1.active != "inactive" || $1.name.localizedCaseInsensitiveContains("magpie")
                    return firstPriority && !secondPriority
                }
                unitsError = nil
            } catch { unitsError = message(for: error) }
            do {
                processes = Array(try await processesResult.get().sorted { $0.cpu > $1.cpu }.prefix(8))
                processesError = nil
            } catch { processesError = message(for: error) }
            await runner.disconnect()
        } catch {
            let text = message(for: error)
            portsError = text
            containersError = text
            unitsError = text
            processesError = text
        }
        lastUpdated = Date()
    }

    private func fetch<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }

    private func message(for error: Error) -> String {
        ErrorMessages.chinese(for: error)
    }
}
