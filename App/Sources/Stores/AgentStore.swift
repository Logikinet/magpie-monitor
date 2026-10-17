import Foundation
import Observation
import MagpieKit

@MainActor @Observable
final class AgentStore {
    private(set) var routes: [Route] = []
    private(set) var totals: TraceTotals?
    private(set) var status: PollStatus = .stopped
    private(set) var authFailed = false
    private(set) var configurationMissing = false
    private(set) var concurrency: Concurrency?
    private(set) var cards: [QuotaCard] = []
    private(set) var concurrencyError: String?
    private(set) var quotaError: String?
    @ObservationIgnored private var traceTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var profile: ProfileConfig?
    @ObservationIgnored private var mockMode: Bool?
    @ObservationIgnored private var poller: TracePoller?

    deinit {
        traceTask?.cancel()
        refreshTask?.cancel()
    }

    var statusText: String {
        if authFailed { return "认证失败" }
        switch status {
        case .connecting: return "连接中"
        case .live: return "实时"
        case .backingOff(let delay): return "重试中 \(Int(ceil(delay)))s"
        case .unauthorized: return "认证失败"
        case .stopped: return "已暂停"
        }
    }

    func start(appState: AppState) {
        stop()
        if profile != appState.currentProfile || mockMode != appState.isMockMode {
            routes = []; totals = nil; concurrency = nil; cards = []
            concurrencyError = nil; quotaError = nil; authFailed = false; poller = nil
            profile = appState.currentProfile; mockMode = appState.isMockMode
        }
        let web: WebClient?
        let gateway: GatewayClient?
        if appState.isMockMode {
            let transport = MockTransport(fixtures: [
                "/api/gateway/trace": (try? MockFixtures.data(named: "trace")) ?? Data(),
                "/v1/magpie/concurrency": (try? MockFixtures.data(named: "concurrency")) ?? Data(),
                "/v1/magpie/quotas/cards": (try? MockFixtures.data(named: "quota_cards")) ?? Data()
            ])
            let url = URL(string: "https://example.ts.net")!
            web = WebClient(baseURL: url, runtimeKey: nil, transport: transport, port: 443)
            gateway = GatewayClient(baseURL: url, key: nil, transport: transport)
        } else {
            let key = appState.currentProfile.flatMap {
                try? appState.secretStore.read(account: SecretField.runtimeKey.account(profileID: $0.id))
            }
            web = key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? appState.makeWebClient() : nil
            gateway = appState.makeGatewayClient()
        }
        configurationMissing = web == nil
        guard appState.isActive, let web else { return }
        if poller == nil { poller = TracePoller(source: web) }
        guard let poller else { return }
        let token = generation
        let mock = appState.isMockMode
        authFailed = false; status = .connecting
        traceTask = Task { [weak self] in
            await poller.run { [weak self] event in
                await self?.receive(event, generation: token)
                // Fixtures return immediately instead of waiting on the server.
                if mock { try? await Task.sleep(for: .seconds(1)) }
            }
        }
        let interval = appState.refreshInterval.isFinite ? max(1, appState.refreshInterval) : 20
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(gateway, generation: token)
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
        }
    }

    func stop() {
        generation = UUID()
        traceTask?.cancel(); traceTask = nil
        refreshTask?.cancel(); refreshTask = nil
        // A fresh actor avoids overlapping run() calls during rapid tab switches.
        poller = nil
        status = .stopped
    }

    private func receive(_ event: TraceEvent, generation token: UUID) {
        guard token == generation else { return }
        switch event {
        case .status(let value):
            status = value
            if value == .unauthorized { authFailed = true }
            if value == .live { authFailed = false }
        case .envelope(let envelope):
            if let value = envelope.totals { totals = value }
            // Route IDs are updated as requests complete; seq is the update cursor.
            for route in envelope.routes?.elements ?? [] {
                if let id = route.id?.value { routes.removeAll { $0.id?.value == id } }
                routes.append(route)
            }
            routes.sort { ($0.seq?.value ?? 0) > ($1.seq?.value ?? 0) }
            routes = Array(routes.prefix(200))
        }
    }

    private func refresh(_ client: GatewayClient?, generation token: UUID) async {
        guard let client else {
            concurrencyError = "请在设置中配置网关地址和密钥。"
            quotaError = concurrencyError
            return
        }
        async let lanes = result { try await client.concurrency() }
        async let quotas = result { try await client.quotaCards() }
        let (laneResult, quotaResult) = await (lanes, quotas)
        guard !Task.isCancelled, token == generation else { return }
        switch laneResult {
        case .success(let value): concurrency = value; concurrencyError = nil
        case .failure(let error): concurrencyError = MagpieError.map(error).localizedChinese
        }
        switch quotaResult {
        case .success(let value): cards = value.data.elements; quotaError = nil
        case .failure(let error): quotaError = MagpieError.map(error).localizedChinese
        }
    }

    private func result<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
}
