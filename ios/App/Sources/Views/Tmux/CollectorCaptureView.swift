import SwiftUI
import UIKit
import MagpieKit

struct CollectorCaptureView: View {
    let target: String
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var live = true
    @State private var lines = 300
    @State private var text = ""
    @State private var error: String?
    @State private var followsOutput = true
    private var refreshID: String { "\(live)-\(lines)-\(scenePhase == .active)-\(appState.isActive)-\(appState.currentProfile?.id.uuidString ?? "demo")-\(appState.isMockMode)" }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(String(localized: "实时监看"), isOn: $live)
                Toggle(String(localized: "跟随输出"), isOn: $followsOutput)
                Picker(String(localized: "行数"), selection: $lines) {
                    ForEach([100, 300, 1000, 2000], id: \.self) { Text($0.formatted()).tag($0) }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(DS.Palette.red) }
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading) {
                            Text(CollectorTerminalText.render(text.isEmpty ? String(localized: "等待终端输出") : text))
                                .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            Color.clear.frame(height: 1).id("bottom")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(DS.Palette.hex("0a0e12"))
                    .simultaneousGesture(DragGesture().onChanged { _ in followsOutput = false })
                    .onChange(of: text) { _, _ in if followsOutput { proxy.scrollTo("bottom", anchor: .bottom) } }
                    Button(String(localized: "滚动到底部")) { followsOutput = true; proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }.padding(16).background(DS.Palette.bg)
                .navigationTitle(target).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "关闭")) { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button(String(localized: "复制输出")) { UIPasteboard.general.string = String(CollectorTerminalText.render(text).characters) } }
                }
        }
        .task(id: refreshID) {
            guard scenePhase == .active, appState.isActive else { return }
            repeat {
                guard !Task.isCancelled, let client = appState.makeCollectorClient() else { return }
                do {
                    let capture = try await client.capture(target: target, lines: lines, ansi: true)
                    try Task.checkCancellation()
                    text = capture.string("text") ?? capture.string("raw") ?? ""
                    error = nil
                } catch { if Task.isCancelled { return }; self.error = ErrorMessages.chinese(for: error) }
                guard live else { return }
                do { try await Task.sleep(for: .milliseconds(2500)) } catch { return }
            } while !Task.isCancelled
        }
    }
}
