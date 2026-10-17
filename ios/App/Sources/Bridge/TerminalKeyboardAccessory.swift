import UIKit

@MainActor
final class TerminalKeyboardAccessory: UIInputView {
    var send: (([UInt8]) -> Void)?
    private(set) var controlEnabled = false

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 52), inputViewStyle: .keyboard)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = DS.Spacing.xSmall
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: DS.Spacing.xSmall),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -DS.Spacing.xSmall),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        let keys: [(String, String, [UInt8])] = [
            ("Esc", String(localized: "退出键"), [27]), ("Tab", String(localized: "制表键"), [9]),
            ("Ctrl", String(localized: "控制键，点按切换锁定"), []),
            ("↑", String(localized: "上方向键"), [27, 91, 65]), ("↓", String(localized: "下方向键"), [27, 91, 66]),
            ("←", String(localized: "左方向键"), [27, 91, 68]), ("→", String(localized: "右方向键"), [27, 91, 67]),
            ("|", String(localized: "竖线"), [124]), ("/", String(localized: "斜线"), [47]), ("-", String(localized: "连字符"), [45]),
            ("~", String(localized: "波浪号"), [126]), ("⌃b", String(localized: "tmux 前缀，控制键加 b"), [2]),
        ]
        for (title, label, bytes) in keys {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.title = title
            button.configuration = configuration
            button.titleLabel?.font = .preferredFont(forTextStyle: .body)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.accessibilityLabel = label
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addAction(
                UIAction { [weak self, weak button] _ in
                    guard let self else { return }
                    if title == "Ctrl" {
                        self.controlEnabled.toggle()
                        button?.isSelected = self.controlEnabled
                        button?.accessibilityValue = self.controlEnabled ? String(localized: "已锁定") : String(localized: "未锁定")
                        button?.backgroundColor = self.controlEnabled ? .tertiarySystemFill : .clear
                    } else {
                        self.send?(self.modified(bytes))
                    }
                }, for: .touchUpInside)
            if title == "Ctrl" { button.accessibilityValue = String(localized: "未锁定") }
            stack.addArrangedSubview(button)
        }
    }

    func modified(_ bytes: [UInt8]) -> [UInt8] {
        guard controlEnabled, bytes.count == 1, let byte = bytes.first else { return bytes }
        if (64...95).contains(byte) || (97...122).contains(byte) { return [byte & 0x1f] }
        if byte == 32 { return [0] }
        if byte == 63 { return [127] }
        return bytes
    }

    required init?(coder: NSCoder) { fatalError("不支持从归档创建键盘附件") }
}
