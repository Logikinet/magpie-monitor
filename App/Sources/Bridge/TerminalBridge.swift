import SwiftUI
import UIKit
@preconcurrency import SwiftTerm
import SSHKit

@MainActor
struct TerminalBridge: UIViewRepresentable {
    let channel: SSHPTYChannel?
    let isDemo: Bool
    let onEnd: @MainActor (SSHPTYChannel, Error?) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(onEnd: onEnd) }

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.inputAccessoryView = context.coordinator.accessory
        view.accessibilityLabel = isDemo ? "模拟终端" : "远程 tmux 终端"
        configure(view)
        context.coordinator.bind(channel, view: view)
        if isDemo {
            let demo = """
                magpie · tmux 演示

                $ tmux list-sessions
                demo: 1 windows (attached)

                $ printf '终端已就绪\\n'
                终端已就绪

                [demo] 0:shell*                 模拟数据
                """.replacingOccurrences(of: "\n", with: "\r\n")
            view.feed(byteArray: Array(demo.utf8)[...])
        }
        return view
    }

    func updateUIView(_ view: TerminalView, context: Context) {
        // Read these environment values so UIKit appearance and font update with SwiftUI.
        _ = dynamicTypeSize
        _ = colorScheme
        configure(view)
        context.coordinator.bind(channel, view: view)
    }

    private func configure(_ view: TerminalView) {
        let base = UIFont.monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base, compatibleWith: view.traitCollection)
        if view.font.pointSize != font.pointSize { view.font = font }
        view.nativeForegroundColor = UIColor.label.resolvedColor(with: view.traitCollection)
        view.nativeBackgroundColor = UIColor.systemBackground.resolvedColor(with: view.traitCollection)
        view.isUserInteractionEnabled = channel != nil && !isDemo
        if channel == nil { view.resignFirstResponder() }
    }

    static func dismantleUIView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.stop()
        view.terminalDelegate = nil
        view.resignFirstResponder()
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        enum Input {
            case bytes([UInt8])
            case size(Int, Int)
        }
        let accessory = TerminalKeyboardAccessory()
        private var channel: SSHPTYChannel?
        private var reader: Task<Void, Never>?
        private var writer: Task<Void, Never>?
        private var input: AsyncStream<Input>.Continuation?
        private let onEnd: @MainActor (SSHPTYChannel, Error?) -> Void

        init(onEnd: @escaping @MainActor (SSHPTYChannel, Error?) -> Void) {
            self.onEnd = onEnd
            super.init()
            accessory.send = { [weak self] bytes in self?.input?.yield(.bytes(bytes)) }
        }

        func bind(_ channel: SSHPTYChannel?, view: TerminalView) {
            guard self.channel !== channel else { return }
            stop()
            guard let channel else { return }
            self.channel = channel
            let stream = AsyncStream<Input>.makeStream()
            input = stream.continuation
            let onEnd = onEnd
            // A single consumer preserves keystroke and resize order across suspension.
            writer = Task {
                do {
                    for await event in stream.stream {
                        try Task.checkCancellation()
                        switch event {
                        case .bytes(let bytes): try await channel.send(bytes)
                        case .size(let cols, let rows): try await channel.resize(cols: cols, rows: rows)
                        }
                    }
                } catch {
                    if !Task.isCancelled { onEnd(channel, error) }
                }
            }
            reader = Task { [weak view] in
                for await bytes in channel.output {
                    guard !Task.isCancelled, let view else { return }
                    view.feed(byteArray: bytes[...])
                }
                guard !Task.isCancelled else { return }
                let error = await channel.terminalError
                onEnd(channel, error)
            }
            let terminal = view.getTerminal()
            sizeChanged(source: view, newCols: terminal.cols, newRows: terminal.rows)
        }

        func stop() {
            input?.finish()
            input = nil
            reader?.cancel()
            writer?.cancel()
            reader = nil
            writer = nil
            channel = nil
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard newCols > 0, newRows > 0 else { return }
            input?.yield(.size(newCols, newRows))
        }
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            input?.yield(.bytes(accessory.modified(Array(data))))
        }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {
            if let text = String(data: content, encoding: .utf8) { UIPasteboard.general.string = text }
        }
        func clipboardRead(source: TerminalView) -> Data? { nil }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    }
}
