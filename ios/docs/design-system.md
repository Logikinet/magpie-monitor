# magpie iOS 设计系统

目标是让运行状态一眼可读，让复杂数据保持层次清楚。使用少量一致的系统样式；不为装饰增加颜色、渐变或动效。本文面向 iOS 17 及以上。

## 布局与信息密度

- 概览、Agent、服务等监控页面按主题分组。先呈现连接与异常，再呈现配额、请求和详细信息。
- 指标卡片只放一个主要数值、简短标题和可选说明。重要状态需同时有图标和文字，不依赖颜色或图表单独传递含义。
- iPhone 使用单列或内容自然换行的两列卡片；优先保证标题和值完整可读。避免将长技术标识压进狭窄列。
- iPad 与宽窗口可使用自适应两至三列网格，相关卡片成组，限制文本区域宽度；保留清晰的章节顺序，不把空白填满。
- 状态变化应简洁、稳定；避免持续闪烁和自动滚动。尊重减少动态效果设置。

## 颜色与状态

- 只使用 SwiftUI / UIKit 系统语义色（如 `primary`、`secondary`、`.background.secondary`、系统绿/橙/红）。由系统适配浅色、深色与对比度，不定义固定 RGB 色值。
- 状态色只作辅助。每个状态都用 SF Symbol 与中文文字共同表达：

| 状态 | 系统色 | SF Symbols | 中文标签 |
| --- | --- | --- | --- |
| 正常 | 绿色 | `checkmark.circle.fill` | 正常 |
| 注意 | 橙色 | `exclamationmark.triangle.fill` | 注意 |
| 错误 | 红色 | `xmark.circle.fill` | 错误 |
| 中性 / 未知 | 次要色 | `minus.circle` | 未知 |
| 不安全连接 | 橙色 | `lock.open.fill` | 不安全（HTTP） |
| 模拟数据 | 次要色 | `play.rectangle` | 模拟数据 |

徽标可补充更具体的可见文字；图标应保持辅助，不能替代描述。错误信息提供明确原因和可行操作。

## 字体与数据

- 正文和层级使用 Dynamic Type 文本样式：页面标题 `.largeTitle` / `.title`，区块标题 `.headline`，内容 `.body`，辅助信息 `.subheadline` / `.footnote`。
- 数值使用 `.monospacedDigit()` 保持刷新时的位宽稳定；终端输出、ID、模型名等技术 token 使用等宽字形，并允许复制或换行，不强行翻译。
- 中文与英文混排直接使用系统字体和自然断行，不插入手工空格来调整字距。短标签避免不必要的中英重复。
- 日期、时间、百分比和数字使用 Foundation 的 Locale 感知格式化，不拼接固定地区格式。

## 间距与形状

使用统一间距：`4 / 8 / 12 / 16 / 24 pt`。4 用于紧邻元素，8 用于相关内容，12 用于卡片内部，16 用于常规内边距，24 用于区块之间。布局需要时可使用系统默认边距。

圆角只采用两档：小型徽标或紧凑控件 8 pt，卡片 12 pt；大容器使用系统呈现样式。卡片使用系统分组背景与连续圆角，避免描边、阴影叠加造成装饰感。

## 无障碍与本地化

- 优先使用可缩放的语义字体；大字级时允许横排变为纵排，内容可滚动，避免固定高度裁切。
- 对图标按钮提供中文 VoiceOver 标签；相关状态内容组合朗读。装饰图标从辅助技术中隐藏。状态颜色不可作为唯一提示。
- 配额进度需提供项目名称、使用量、上限和百分比的可访问标签和值；不只依赖进度条颜色。
- 不用动画作为唯一反馈。动画应短且有用途，并检查 `accessibilityReduceMotion`；可用静态状态替代。
- 重要触控目标至少 44 × 44 pt。布局应适应 iPhone、iPad 分屏和窗口尺寸变化。

## 参考

- Apple Human Interface Guidelines — [布局](https://developer.apple.com/design/human-interface-guidelines/layout)、[颜色](https://developer.apple.com/design/human-interface-guidelines/color)、[无障碍](https://developer.apple.com/design/human-interface-guidelines/accessibility)、[图表](https://developer.apple.com/design/human-interface-guidelines/charts)
- Apple Developer Documentation — [SwiftUI `Font`](https://developer.apple.com/documentation/swiftui/font)、[SwiftUI `DynamicTypeSize`](https://developer.apple.com/documentation/swiftui/dynamictypesize)、[SwiftUI `ContentUnavailableView`](https://developer.apple.com/documentation/swiftui/contentunavailableview)
