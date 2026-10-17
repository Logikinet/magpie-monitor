import Foundation
import Observation
import MagpieKit

enum ActivityPeriod: String, CaseIterable, Identifiable {
    case today = "today"
    case sevenDays = "7d"
    case thirtyDays = "30d"

    var id: String { rawValue }
    var title: String {
        switch self { case .today: "今天"; case .sevenDays: "近 7 天"; case .thirtyDays: "近 30 天" }
    }
}

@MainActor @Observable
final class ActivityStore {
    private(set) var rows: [LedgerRow] = []
    private(set) var series: [SeriesPoint] = []
    private(set) var total = 0
    private(set) var offset = 0
    private(set) var calls = 0
    private(set) var inputTokens = 0
    private(set) var outputTokens = 0
    private(set) var cost = 0.0
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var lastUpdated: Date?
    private(set) var agentOptions: [LedgerNamed] = []
    private(set) var providerOptions: [LedgerNamed] = []
    private(set) var modelOptions: [String] = []
    var period: ActivityPeriod = .today
    var agentFilter = ""
    var providerFilter = ""
    var modelFilter = ""
    private let pageSize = 50

    var hasMore: Bool { offset < total }

    func refresh(appState: AppState) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        rows = []; series = []; total = 0; offset = 0
        await loadPage(appState: appState, replace: true)
    }

    func loadMore(appState: AppState) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await loadPage(appState: appState, replace: false)
    }

    private func loadPage(appState: AppState, replace: Bool) async {
        guard let client = appState.makeGatewayClient() else {
            error = "请先选择服务器配置。"
            return
        }
        var filters: [String: String] = [:]
        if !agentFilter.isEmpty { filters["agent"] = agentFilter }
        if !providerFilter.isEmpty { filters["provider"] = providerFilter }
        if !modelFilter.isEmpty { filters["model"] = modelFilter }
        do {
            let page = try await client.requests(period: period.rawValue, offset: replace ? 0 : offset, limit: pageSize, filters: filters)
            let incoming = page.rows.elements
            if replace {
                rows = incoming
                series = page.series?.elements ?? []
                agentOptions = page.agents?.elements ?? []
                providerOptions = page.providers?.elements ?? []
                modelOptions = Array(Set(incoming.compactMap(\.model).filter { !$0.isEmpty })).sorted()
                calls = page.calls?.value ?? 0
                inputTokens = page.input?.value ?? 0
                outputTokens = page.output?.value ?? 0
                cost = page.cost?.value ?? 0
            } else {
                var known = Set(rows.map(identity))
                rows.append(contentsOf: incoming.filter { known.insert(identity($0)).inserted })
                modelOptions = Array(Set(modelOptions + incoming.compactMap(\.model))).sorted()
            }
            offset = (page.offset?.value ?? (replace ? 0 : offset)) + incoming.count
            total = page.total?.value ?? rows.count
            error = nil
            lastUpdated = Date()
        } catch {
            self.error = (error as? MagpieError)?.localizedChinese ?? "读取请求记录失败，请检查连接后重试。"
        }
    }

    private func identity(_ row: LedgerRow) -> String {
        row.id
    }
}
