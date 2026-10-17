import Charts
import SwiftUI
import MagpieKit

@MainActor
struct ActivityView: View {
    @Environment(AppState.self) private var appState
    @State private var store = ActivityStore()
    @State private var selectedRow: LedgerRow?
    @State private var isAtTop = true

    private let columns = [GridItem(.adaptive(minimum: 150), alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.large) {
                GeometryReader { proxy in
                    Color.clear.preference(key: ActivityTopKey.self, value: proxy.frame(in: .named("activityScroll")).minY >= -8)
                }
                .frame(height: 0)
                controls
                if let error = store.error, store.rows.isEmpty {
                    unavailable(error)
                } else {
                    trendSection
                    metrics
                    filters
                    requestList
                }
            }
            .padding(DS.Spacing.medium)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: "activityScroll")
        .onPreferenceChange(ActivityTopKey.self) { isAtTop = $0 }
        .refreshable { await store.refresh(appState: appState) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refresh(appState: appState) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(String(localized: "刷新请求记录"))
                .disabled(store.isLoading)
            }
        }
        .sheet(item: $selectedRow) { row in
            NavigationStack { ActivityRowDetail(row: row) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(
            id: RefreshContext(
                profile: appState.currentProfile,
                isMockMode: appState.isMockMode,
                isActive: appState.isActive,
                filters: [store.period.rawValue, store.agentFilter, store.providerFilter, store.modelFilter]
            )
        ) {
            guard appState.isActive else { return }
            await store.refresh(appState: appState)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(appState.refreshInterval)) } catch { return }
                guard appState.isActive, isAtTop else { continue }
                await store.refresh(appState: appState)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: DS.Spacing.small) {
            Picker(String(localized: "统计周期"), selection: $store.period) {
                ForEach(ActivityPeriod.allCases) { period in Text(period.title).tag(period) }
            }
            .pickerStyle(.segmented)
            if store.isLoading { ProgressView().accessibilityLabel(String(localized: "正在加载")) }
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.mediumSmall) {
            SectionHeader(title: String(localized: "请求趋势"), subtitle: String(localized: "按服务器返回的时间分桶"))
            if store.series.isEmpty {
                Text(String(localized: "暂无趋势数据")).font(.subheadline).foregroundStyle(.secondary)
            } else {
                let points = Array(store.series.enumerated())
                let hasDates = points.allSatisfy { $0.element.time?.date != nil }
                Chart(points, id: \.offset) { index, point in
                    let value = """
                    \(point.calls?.value ?? 0) 次请求，\
                    \(point.tokens?.value ?? 0) 个令牌，\
                    费用 \((point.cost?.value ?? 0).formatted(.number.precision(.fractionLength(4))))
                    """
                    if hasDates, let date = point.time?.date {
                        BarMark(
                            x: .value(String(localized: "时间"), date, unit: store.bucket == "hour" ? .hour : .day),
                            y: .value(String(localized: "请求数"), point.calls?.value ?? 0)
                        )
                        .foregroundStyle(.tint)
                        .accessibilityLabel(point.label ?? String(format: String(localized: "时间段 %@"), locale: Locale.current, String(describing: index + 1)))
                        .accessibilityValue(value)
                    } else {
                        BarMark(
                            x: .value(String(localized: "时间"), point.label ?? "\(index)"),
                            y: .value(String(localized: "请求数"), point.calls?.value ?? 0)
                        )
                        .foregroundStyle(.tint)
                        .accessibilityLabel(point.label ?? String(format: String(localized: "时间段 %@"), locale: Locale.current, String(describing: index + 1)))
                        .accessibilityValue(value)
                    }
                }
                .chartXAxis {
                    if hasDates {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisTick()
                            if store.bucket == "hour" {
                                AxisValueLabel(format: .dateTime.hour())
                            } else {
                                AxisValueLabel(format: .dateTime.month().day())
                            }
                        }
                    } else {
                        AxisMarks(values: store.series.enumerated().compactMap { index, point in
                            index.isMultiple(of: max(1, (store.series.count + 3) / 4)) ? point.label : nil
                        }) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel()
                        }
                    }
                }
                .chartYAxisLabel(String(localized: "请求数"))
                .frame(height: 180)
                .accessibilityLabel(String(localized: "请求趋势图"))
            }
        }
        .padding(DS.Spacing.medium)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private var metrics: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Spacing.mediumSmall) {
            MetricCard(title: String(localized: "请求"), value: store.calls.formatted(), systemImage: "arrow.left.arrow.right")
            MetricCard(title: String(localized: "输入令牌"), value: store.inputTokens.formatted(), systemImage: "arrow.down.left")
            MetricCard(title: String(localized: "输出令牌"), value: store.outputTokens.formatted(), systemImage: "arrow.up.right")
            MetricCard(title: String(localized: "费用"), value: store.cost.formatted(.number.precision(.fractionLength(0...4))), systemImage: "creditcard")
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            SectionHeader(title: String(localized: "筛选"))
            filterPicker(String(localized: "全部 Agent"), selection: $store.agentFilter, options: store.agentOptions.map { ($0.id, $0.name) })
            filterPicker(String(localized: "全部提供方"), selection: $store.providerFilter, options: store.providerOptions.map { ($0.id, $0.name) })
            filterPicker(String(localized: "全部模型"), selection: $store.modelFilter, options: store.modelOptions.map { ($0, $0) })
        }
    }

    private func filterPicker(_ title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        Picker(title, selection: selection) {
            Text(title).tag("")
            ForEach(options.indices, id: \.self) { index in
                Text(options[index].1).tag(options[index].0)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.medium)
        .frame(minHeight: 44)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
    }

    private var requestList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            SectionHeader(title: String(localized: "请求记录"), subtitle: String(format: String(localized: "共 %@ 条"), locale: Locale.current, String(describing: store.total.formatted())))
            if store.rows.isEmpty {
                EmptyStateView(title: String(localized: "暂无请求记录"), description: String(localized: "调整周期或筛选条件后重试。"), systemImage: "tray")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.rows.enumerated()), id: \.offset) { index, row in
                        Button {
                            selectedRow = row
                        } label: {
                            ActivityRowView(row: row)
                        }
                        .buttonStyle(.plain)
                        Divider()
                        if index == store.rows.count - 1 {
                            Color.clear.frame(height: 1).task {
                                await store.loadMore(appState: appState)
                            }
                        }
                    }
                    if store.isLoadingMore { ProgressView().frame(maxWidth: .infinity).padding() }
                }
                .padding(.horizontal, DS.Spacing.medium)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
            if let error = store.error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }

    private func unavailable(_ message: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "无法读取动态"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(String(localized: "重试")) { Task { await store.refresh(appState: appState) } }
        }
    }
}

private struct ActivityRowView: View {
    let row: LedgerRow

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.agentName ?? row.agent ?? String(localized: "未知智能体")).font(.headline).lineLimit(1)
                Spacer(minLength: DS.Spacing.small)
                Text(row.time?.date ?? Date.distantPast, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(row.model ?? String(localized: "未知模型")).font(.subheadline.monospaced()).textSelection(.enabled).lineLimit(2)
            HStack(spacing: DS.Spacing.mediumSmall) {
                Text(row.providerName ?? row.provider ?? String(localized: "未知提供方"))
                Spacer(minLength: 0)
                Text(String(format: String(localized: "入 %@ · 出 %@"), locale: Locale.current, String(describing: row.input?.value ?? 0), String(describing: row.output?.value ?? 0))).monospacedDigit()
                Text((row.cost?.value ?? 0).formatted(.number.precision(.fractionLength(0...4))))
                    .monospacedDigit()
            }
            .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: DS.Spacing.mediumSmall) {
                if row.swapped == true { StatusBadge(kind: .warning, text: String(localized: "已切换")) }
                if row.routed == true { StatusBadge(kind: .neutral, text: String(localized: "已路由")) }
                if row.error != nil || (row.status?.value ?? 0) >= 400 { StatusBadge(kind: .error, text: String(localized: "错误")) }
            }
        }
        .padding(.vertical, DS.Spacing.medium)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "查看请求详情"))
    }
}

private struct ActivityTopKey: PreferenceKey {
    static var defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = nextValue() }
}

private struct ActivityRowDetail: View {
    let row: LedgerRow
    private var fields: [(String, String)] {
        [
            (String(localized: "时间"), row.time?.rawString ?? String(localized: "未知")), (String(localized: "操作"), row.operation ?? String(localized: "未知")),
            ("Agent", row.agentName ?? row.agent ?? String(localized: "未知")), (String(localized: "图标"), row.icon ?? String(localized: "未知")),
            (String(localized: "模型"), row.model ?? String(localized: "未知")), (String(localized: "请求模型"), row.requested ?? String(localized: "未知")),
            (String(localized: "响应模型"), row.served ?? String(localized: "未知")), (String(localized: "提供方"), row.providerName ?? row.provider ?? String(localized: "未知")),
            (String(localized: "主机"), row.host ?? String(localized: "未知")), (String(localized: "状态码"), row.status.map { "\($0.value)" } ?? String(localized: "未知")),
            (String(localized: "输入令牌"), "\(row.input?.value ?? 0)"), (String(localized: "输出令牌"), "\(row.output?.value ?? 0)"),
            (String(localized: "缓存读取"), "\(row.cacheRead?.value ?? 0)"), (String(localized: "缓存写入"), "\(row.cacheWrite?.value ?? 0)"),
            (String(localized: "费用"), (row.cost?.value ?? 0).formatted()), (String(localized: "已计价"), row.priced == true ? String(localized: "是") : String(localized: "否")),
            (String(localized: "已切换"), row.swapped == true ? String(localized: "是") : String(localized: "否")), (String(localized: "已路由"), row.routed == true ? String(localized: "是") : String(localized: "否")),
            (String(localized: "错误"), row.error ?? row.errorType ?? String(localized: "无")), (String(localized: "会话"), row.session ?? String(localized: "未知")),
            (String(localized: "请求 ID"), row.requestID ?? String(localized: "未知")), (String(localized: "来源"), row.source ?? String(localized: "未知")),
        ]
    }

    var body: some View {
        List {
            ForEach(fields.indices, id: \.self) { index in
                LabeledContent(fields[index].0) {
                    Text(fields[index].1).textSelection(.enabled).multilineTextAlignment(.trailing)
                }
            }
        }
        .navigationTitle(String(localized: "请求详情"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
