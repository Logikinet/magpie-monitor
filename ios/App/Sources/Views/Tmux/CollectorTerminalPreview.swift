import SwiftUI
import MagpieKit

struct CollectorTerminalPreview: View {
    let pane: CollectorRecord
    private var lines: [String] {
        guard case .array(let values) = pane.fields["preview"] else { return [] }
        return values.compactMap { value in
            if case .string(let line) = value { return line }
            return nil
        }
    }
    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                titleBar
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(lines.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(DS.Palette.hex("9fd4a0"))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(12)
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .background(DS.Palette.hex("000000"))
            }
            .background(DS.Palette.hex("000000"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.Palette.hex("1c242e")))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "终端预览"))
            .accessibilityValue(lines.joined(separator: "\n"))
        }
    }
    private var titleBar: some View {
        return HStack(spacing: 8) {
            Circle().fill(DS.Palette.hex("ff5f57")).frame(width: 10, height: 10)
            Circle().fill(DS.Palette.hex("febc2e")).frame(width: 10, height: 10)
            Circle().fill(DS.Palette.hex("28c840")).frame(width: 10, height: 10)
            Text(pane.string("command") ?? "terminal")
                .font(.caption.monospaced())
                .foregroundStyle(DS.Palette.hex("9fd4a0"))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DS.Palette.hex("1c242e"))
        .accessibilityHidden(true)
    }
}