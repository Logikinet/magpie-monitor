import SwiftUI
import MagpieKit

struct ActivityCommitCard: View {
    let event: CollectorRecord
    private var files: [CollectorRecord] { return event.records("files") }
    private var repoColor: Color {
        let colors = [DS.Palette.accent, DS.Palette.green, DS.Palette.hex("a78bfa"), DS.Palette.warn]
        let hash = (event.string("repo") ?? "").utf8.reduce(0) { (($0 &* 31) &+ Int($1)) & 0xfff }
        return colors[hash % colors.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HorizontalChipRow(minHeight: 28) {
                Text(event.string("repo") ?? "—")
                    .foregroundStyle(repoColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(repoColor.opacity(0.12), in: Capsule())
                Text(event.string("short_sha") ?? String((event.string("sha") ?? "—").prefix(7))).monospaced()
                Text(event.string("branch") ?? "—")
                Text(origin).padding(.horizontal, 8).padding(.vertical, 4).background(DS.Palette.chip, in: Capsule())
                if hasImage {
                    Text(String(localized: "图片")).padding(.horizontal, 8).padding(.vertical, 4).background(DS.Palette.chip, in: Capsule())
                }
            }
            .font(.caption)
            Text(event.string("subject") ?? event.string("title") ?? "—").font(.headline).fixedSize(horizontal: false, vertical: true)
            Text("\(event.string("author") ?? "—") · \(Date(timeIntervalSince1970: event.number("ts") ?? 0).formatted(.dateTime.hour().minute()))")
                .font(.caption)
                .foregroundStyle(DS.Palette.soft)
            ForEach(Array(files.prefix(8).enumerated()), id: \.offset) { _, file in
                fileRow(file)
            }
            if files.count > 8 {
                Text(String(format: String(localized: "另有 %@ 个文件"), locale: Locale.current, String(describing: (files.count - 8).formatted())))
                    .font(.caption)
                    .foregroundStyle(DS.Palette.soft)
            }
            if let url = githubURL {
                Link(String(localized: "GitHub 差异"), destination: url).frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .routingCard()
    }

    private var origin: String {
        switch event.string("origin") {
        case "both": return String(localized: "已同步")
        case "gh": return "GitHub"
        default: return String(localized: "本地")
        }
    }
    private var hasImage: Bool {
        if event.flag("image") == true { return true }
        let extensions = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif"]
        return files.contains { file in
            extensions.contains(URL(fileURLWithPath: file.string("path") ?? "").pathExtension.lowercased())
        }
    }
    private var githubURL: URL? {
        guard let raw = event.string("url"), let url = URL(string: raw), url.scheme == "https", url.host == "github.com" else { return nil }
        return url
    }
    private func fileRow(_ file: CollectorRecord) -> some View {
        let status = file.string("status") ?? "M"
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(status).font(.caption.monospaced().bold()).foregroundStyle(fileColor(status)).frame(width: 16, alignment: .center)
            Text(file.string("path") ?? "—").font(.caption.monospaced()).textSelection(.enabled)
        }
    }
    private func fileColor(_ status: String) -> Color {
        switch status {
        case "A": return DS.Palette.green
        case "D": return DS.Palette.red
        case "R": return DS.Palette.hex("a78bfa")
        default: return DS.Palette.warn
        }
    }
}
