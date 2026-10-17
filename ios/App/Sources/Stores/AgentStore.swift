import Foundation
import Observation
import MagpieKit

@MainActor @Observable
final class AgentStore {
    var period = "today"
    private(set) var usageCache: [String: UsageSummary] = [:]
    private(set) var usageUpdated: [String: Date] = [:]
    private(set) var usageError: String?
    var usage: UsageSummary? { usageCache[period] }
    @ObservationIgnored private var webClient: WebClient?
    func loadUsage() async {
        guard let webClient else { return }
        let token = generation
        let requested = period
        do {
            let value = try await webClient.usage(period: requested)
            guard token == generation, !Task.isCancelled else { return }
            usageCache[requested] = value
            usageUpdated[requested] = value.fetchedAt?.date ?? Date()
            if requested == period { usageError = nil }
        } catch {
            if token == generation, requested == period { usageError = String(localized: "用量读取失败") }
        }
    }
    private(set) var groups: [RoutingGroup] = []
    private(set) var providers: [Provider] = []
    private(set) var usageQuotas: [Quota] = []
    private(set) var routingError: String?
    private(set) var now = Date()
    private(set) var pinnedID: Int?
    var seatFilter: String?
    var currentRoute: Route? { RoutingModel.currentRoute(in: routes, pinnedID: pinnedID) }
    func pin(_ route: Route) { pinnedID = route.id?.value }
    func unpin() { pinnedID = nil }
    @ObservationIgnored private var tickerTask: Task<Void, Never>?
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
        tickerTask?.cancel()
        traceTask?.cancel()
        refreshTask?.cancel()
    }

    var statusText: String {
        if authFailed { return String(localized: "认证失败") }
        switch status {
        case .connecting: return String(localized: "连接中")
        case .live: return String(localized: "实时")
        case .backingOff(let delay): return String(format: String(localized: "重试中 %@s"), locale: Locale.current, String(describing: Int(ceil(delay))))
        case .unauthorized: return String(localized: "认证失败")
        case .stopped: return String(localized: "已暂停")
        }
    }

    func start(appState: AppState) {
        stop()
        if profile != appState.currentProfile || mockMode != appState.isMockMode {
            usageCache = [:]
            usageUpdated = [:]
            usageError = nil
            routes = []
            groups = []
            providers = []
            usageQuotas = []
            routingError = nil
            pinnedID = nil
            seatFilter = nil
            totals = nil
            concurrency = nil
            cards = []
            concurrencyError = nil
            quotaError = nil
            authFailed = false
            poller = nil
            profile = appState.currentProfile
            mockMode = appState.isMockMode
        }
        let web: WebClient?
        let gateway: GatewayClient?
        if appState.isMockMode {
            let transport = MockTransport(fixtures: [
                "/api/usage": (try? MockFixtures.data(named: "usage")) ?? Data(),
                "/api/groups": (try? MockFixtures.data(named: "groups")) ?? Data(),
                "/api/providers": (try? MockFixtures.data(named: "providers_usage")) ?? Data(),
                "/api/usage/quotas": (try? MockFixtures.data(named: "usage_quotas")) ?? Data(),
                "/api/gateway/trace": (try? MockFixtures.data(named: "trace")) ?? Data(),
                "/v1/magpie/concurrency": (try? MockFixtures.data(named: "concurrency")) ?? Data(),
                "/v1/magpie/quotas/cards": (try? MockFixtures.data(named: "quota_cards")) ?? Data(),
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
        webClient = web
        configurationMissing = web == nil
        guard appState.isActive, let web else { return }
        if poller == nil { poller = TracePoller(source: web) }
        guard let poller else { return }
        let token = generation
        let mock = appState.isMockMode
        authFailed = false
        status = .connecting
        traceTask = Task { [weak self] in
            await poller.run { [weak self] event in
                await self?.receive(event, generation: token)
                // Fixtures return immediately instead of waiting on the server.
                if mock, case .envelope = event { try? await Task.sleep(for: .seconds(1)) }
            }
        }
        let interval = appState.refreshInterval.isFinite ? max(1, appState.refreshInterval) : 20
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Date()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.loadUsage()
                await self?.refreshRouting(web, generation: token)
                await self?.refresh(gateway, generation: token)
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
        }
    }

    func stop() {
        generation = UUID()
        tickerTask?.cancel()
        tickerTask = nil
        traceTask?.cancel()
        traceTask = nil
        refreshTask?.cancel()
        refreshTask = nil
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
            routes = (envelope.routes?.elements ?? []).sorted { ($0.seq?.value ?? 0) > ($1.seq?.value ?? 0) }
            if let pinnedID, !routes.contains(where: { $0.id?.value == pinnedID }) { self.pinnedID = nil }
        }
    }

    private func refreshRouting(_ client: WebClient, generation token: UUID) async {
        async let groupResult = result { try await client.groups() }
        async let providerResult = result { try await client.providers() }
        async let quotaResult = result { try await client.usageQuotas() }
        let results = await (groupResult, providerResult, quotaResult)
        guard !Task.isCancelled, token == generation else { return }
        var errors: [String] = []
        switch results.0 {
        case .success(let value): groups = value.groups?.elements ?? []
        case .failure(let error): errors.append(ErrorMessages.chinese(for: error))
        }
        switch results.1 {
        case .success(let value): providers = value.providers?.elements ?? []
        case .failure(let error): errors.append(ErrorMessages.chinese(for: error))
        }
        switch results.2 {
        case .success(let value): usageQuotas = value.elements
        case .failure(let error): errors.append(ErrorMessages.chinese(for: error))
        }
        routingError = errors.isEmpty ? nil : errors.joined(separator: "；")
    }

    private func refresh(_ client: GatewayClient?, generation token: UUID) async {
        guard let client else {
            concurrencyError = String(localized: "请在设置中配置网关地址和密钥。")
            quotaError = concurrencyError
            return
        }
        async let lanes = result { try await client.concurrency() }
        async let quotas = result { try await client.quotaCards() }
        let (laneResult, quotaResult) = await (lanes, quotas)
        guard !Task.isCancelled, token == generation else { return }
        switch laneResult {
        case .success(let value):
            concurrency = value
            concurrencyError = nil
        case .failure(let error): concurrencyError = ErrorMessages.chinese(for: error)
        }
        switch quotaResult {
        case .success(let value):
            cards = value.data.elements
            quotaError = nil
        case .failure(let error): quotaError = ErrorMessages.chinese(for: error)
        }
    }

    private func result<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
}
