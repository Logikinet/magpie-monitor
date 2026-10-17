import SwiftUI
import MagpieKit

struct ContextWaffleView: View {
    let route: Route
    @State private var filter = "all"
    @State private var expanded = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let kinds = ["system", "tools", "files", "results", "chat", "memory"]
    private var parts: [PromptPart] { route.prompt?.parts?.elements ?? [] }
    private var cacheHit: String {
        let usage = route.usage?.elements ?? []
        guard !usage.isEmpty, usage.allSatisfy({ $0.input != nil && $0.cacheRead != nil }) else { return "—" }
        let input = usage.reduce(0.0) { $0 + Double(max(0, $1.input?.value ?? 0)) }
        let cached = usage.reduce(0.0) { $0 + Double(max(0, $1.cacheRead?.value ?? 0)) }
        guard input + cached > 0 else { return "—" }
        return (cached / (input + cached)).formatted(.percent.precision(.fractionLength(1)))
    }
    private var capacity: Int? {
        guard let window = route.prompt?.window?.value, let tokens = route.prompt?.tokens?.value,
              max(window, tokens) > 0 else { return nil }
        return max(window, tokens)
    }
    private func color(_ kind: String) -> Color {
        switch kind {
        case "system": DS.Palette.kSystem
        case "tools": DS.Palette.kTools
        case "files": DS.Palette.kFiles
        case "results": DS.Palette.kResults
        case "chat": DS.Palette.kChat
        case "memory": DS.Palette.kMemory
        default: DS.Palette.kFree
        }
    }
    private func title(_ kind: String) -> String {
        switch kind {
        case "all": "全部"
        case "system": "系统"
        case "tools": "工具"
        case "files": "文件"
        case "results": "结果"
        case "chat": "对话"
        case "memory": "记忆"
        default: kind
        }
    }
    private var cells: [String] {
        guard let capacity, !parts.isEmpty else { return Array(repeating: "free", count: 400) }
        var cells: [String] = []
        var cumulative = 0.0
        for part in parts {
            cumulative += Double(max(0, part.tokens?.value ?? 0)) / Double(capacity) * 400
            let end = Int(min(400, cumulative.rounded()))
            if end > cells.count { cells += Array(repeating: part.kind ?? "unknown", count: end - cells.count) }
        }
        return cells + Array(repeating: "free", count: 400 - cells.count)
    }
    private var items: [(String, PromptItem)] {
        parts.filter { filter == "all" || $0.kind == filter }.flatMap { part in
            (part.items?.elements ?? []).map { (part.kind ?? "unknown", $0) }
        }
    }
    var body: some View {
        let values = cells
        return VStack(alignment: .leading, spacing: 12) {
            Text("上下文窗口").font(.headline)
            Text("已用 \(route.prompt?.tokens?.value.formatted() ?? "—") / \(route.prompt?.window?.value.formatted() ?? "—") token")
                .font(.subheadline.monospaced())
            Text("缓存命中：\(cacheHit) · 对话轮数：\(route.prompt?.turns?.value.formatted() ?? "—")").font(.caption.monospaced()).foregroundStyle(DS.Palette.soft)
            if let capacity, !parts.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1.5), count: sizeClass == .compact ? 20 : 40), spacing: 1.5) {
                    ForEach(0..<400, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2).fill(color(values[index])).aspectRatio(1, contentMode: .fit)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("上下文分布，容量 \(capacity) token")
            } else { Text("暂无上下文分布").foregroundStyle(DS.Palette.dim) }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(["all"] + kinds, id: \.self) { kind in
                        Button { filter = kind; expanded = false } label: {
                            Label(title(kind), systemImage: filter == kind ? "checkmark.circle.fill" : "circle.fill")
                                .font(.caption).foregroundStyle(kind == "all" ? DS.Palette.text : color(kind))
                                .padding(8).frame(minHeight: 44)
                                .background(filter == kind ? DS.Palette.hover : DS.Palette.panel, in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(filter == kind ? .isSelected : [])
                    }
                }
            }
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if filter == "all" || filter == part.kind {
                    Text("\(title(part.kind ?? "—")) · \(part.tokens?.value.formatted() ?? "—") token")
                        .font(.caption.monospaced())
                }
            }
            ForEach(Array((expanded ? items : Array(items.prefix(10))).enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .top) {
                    Text(entry.1.name ?? "—").textSelection(.enabled)
                    Spacer()
                    Text(entry.1.tokens?.value.formatted() ?? "—").monospacedDigit()
                }.font(.caption)
            }
            if items.count > 10 {
                Button(expanded ? "收起条目" : "显示全部 \(items.count) 项") { expanded.toggle() }.frame(minHeight: 44)
            }
            Text([route.session, route.folder].compactMap { $0 }.joined(separator: " › "))
                .font(.caption.monospaced()).foregroundStyle(DS.Palette.dim).textSelection(.enabled)
        }
    }
}
