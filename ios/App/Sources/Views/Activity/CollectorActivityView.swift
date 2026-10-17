import SwiftUI
import MagpieKit

struct CollectorActivityView: View {
    @Environment(AppState.self) private var appState
    @State private var events: [CollectorRecord] = []
    @State private var error: String?
    @State private var loading = true
    @State private var filter = "all"
    @State private var showSnapshots = false
    private let filters = ["all", "commit", "img", "both", "local", "done", "watchdog"]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HorizontalChipRow {
                    ForEach(filters, id: \.self) { item in
                        Button(chipTitle(item)) { filter = item }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .tint(filter == item ? DS.Palette.accent : .secondary)
                            .accessibilityAddTraits(filter == item ? .isSelected : [])
                    }
                }
                Toggle(String(localized: "展开自动发布记录"), isOn: $showSnapshots)
                if loading { ProgressView() }
                if let error {
                    Text(error).foregroundStyle(DS.Palette.red)
                    Button(String(localized: "重试")) { Task { await refresh() } }.frame(minHeight: 44)
                }
                if !loading && error == nil && groups.isEmpty { Text(String(localized: "暂无数据")) }
                ForEach(groups) { group in
                    Text(dayHeading(group.day, count: group.rows.count)).font(.headline)
                    ForEach(Array(group.rows.enumerated()), id: \.offset) { index, event in
                        timelineRow(event, first: index == 0, last: index == group.rows.count - 1)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Palette.bg)
        .refreshable { await refresh() }
        .task(id: RefreshContext(profile: appState.currentProfile, isMockMode: appState.isMockMode, isActive: appState.isActive)) {
            events = []
            error = nil
            guard appState.isActive else { return }
            await refresh()
        }
    }

    private var visible: [CollectorRecord] {
        let sorted = events.sorted { timestamp($0) > timestamp($1) }
        if showSnapshots { return sorted }
        var keptSnapshot = false
        var rows: [CollectorRecord] = []
        for event in sorted {
            if event.flag("auto_publish") == true {
                if keptSnapshot { continue }
                keptSnapshot = true
            }
            rows.append(event)
        }
        return rows
    }
    private var groups: [DayGroup] {
        let rows = visible.filter { matches($0, filter) }
        let days = Array(Set(rows.map { Calendar.current.startOfDay(for: timestamp($0)) })).sorted(by: >)
        return days.map { day in
            DayGroup(day: day, rows: rows.filter { Calendar.current.isDate(timestamp($0), inSameDayAs: day) })
        }
    }
    private func timelineRow(_ event: CollectorRecord, first: Bool, last: Bool) -> some View {
        return HStack(alignment: .top, spacing: 12) {
            Circle().fill(DS.Palette.accent).frame(width: 10, height: 10).padding(.top, 22).accessibilityHidden(true)
            ActivityCommitCard(event: event)
        }
        .background(alignment: .topLeading) { spine(first: first, last: last) }
    }
    private func spine(first: Bool, last: Bool) -> some View {
        let line = DS.Palette.dim.opacity(0.45)
        return VStack(spacing: 0) {
            Rectangle()
                .fill(first ? Color.clear : line)
                .frame(width: 2, height: 27)
            if !last {
                Rectangle()
                    .fill(line)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.leading, 4)
        .accessibilityHidden(true)
    }
    private func timestamp(_ event: CollectorRecord) -> Date {
        return Date(timeIntervalSince1970: event.number("ts") ?? 0)
    }
    private func matches(_ event: CollectorRecord, _ value: String) -> Bool {
        switch value {
        case "commit": return event.string("kind") == "commit"
        case "img": return hasImage(event)
        case "both": return event.string("origin") == "both"
        case "local": return event.string("origin") == "local"
        case "done": return event.string("src") == "done" || event.string("kind") == "complete"
        case "watchdog": return event.string("kind") == "watchdog" || event.string("src") == "watchdog"
        default: return true
        }
    }
    private func hasImage(_ event: CollectorRecord) -> Bool {
        if event.flag("image") == true { return true }
        let extensions = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif"]
        return event.records("files").contains { file in
            extensions.contains(URL(fileURLWithPath: file.string("path") ?? "").pathExtension.lowercased())
        }
    }
    private func chipTitle(_ value: String) -> String {
        let count = visible.filter { matches($0, value) }.count.formatted()
        return "\(title(value)) (\(count))"
    }
    private func title(_ value: String) -> String {
        switch value {
        case "commit": return String(localized: "提交")
        case "img": return String(localized: "图片")
        case "both": return String(localized: "已同步")
        case "local": return String(localized: "本地")
        case "done": return String(localized: "已完成")
        case "watchdog": return String(localized: "守护任务")
        default: return String(localized: "全部")
        }
    }
    private func dayHeading(_ day: Date, count: Int) -> String {
        let iso = day.formatted(Date.VerbatimFormatStyle(
            format: "\(year: .padded(4))-\(month: .twoDigits)-\(day: .twoDigits)",
            timeZone: .current,
            calendar: Calendar(identifier: .gregorian)
        ))
        let when = Calendar.current.isDateInToday(day) ? String(localized: "今天") : day.formatted(.dateTime.weekday(.wide))
        let changes = String(format: String(localized: "%@ 项变更"), locale: Locale.current, String(describing: count.formatted()))
        return "\(iso) · \(when) · \(changes)"
    }
    private func refresh() async {
        guard let client = appState.makeCollectorClient() else {
            loading = false
            error = String(localized: "连接 collector 后可查看提交记录。")
            return
        }
        loading = true
        defer { loading = false }
        do {
            events = try await client.activity().records("events")
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct DayGroup: Identifiable {
    let day: Date
    let rows: [CollectorRecord]
    var id: Date { return day }
}
