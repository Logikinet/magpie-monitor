# magpie-ios 架构设计

> 面向 yetone/magpie LLM 网关的原生 SwiftUI iOS 远程监控应用。
> 本文为设计文档，不含实现代码。所有 API 事实以 `docs/magpie-api-notes.md` 为准。

## 1. 目标与非目标

### 目标（Goals）
- 在 iPhone/iPad 上远程查看 magpie 网关的运行状态、配额、请求流水与实时路由。
- 通过 SSH 远程管理 magpie 所在主机的 docker 容器与 systemd 服务（启动/停止，带确认）。
- 通过内嵌终端远程 `tmux attach`，查看/操作 agent 会话。
- 多服务器 Profile 切换，便于同时监控多台 magpie 实例。
- 纯 Swift 可测核心（MagpieKit），可在 Linux `swift test` 验证模型解析、请求构造、长轮询状态机与 SSH 输出解析。
- 无服务器时可用 Mock 数据模式截图/演示。

### 非目标（Non-goals）
- **不** 部署/启动/配置 magpie 本身（只读监控 + 容器/服务启停，不写 magpie 配置或数据库）。
- **不** 做代码签名/分发（用户自行用 轻松签/LCSign 签名）。
- **不** 提交 `.xcodeproj`（由 XcodeGen 生成）。
- **不** 复用/搬运 vibebuddy 代码（仅参考其 XcodeGen + 本地 SwiftPM + CODE_SIGNING_ALLOWED=NO 的工程组织方式）。
- **不** 做后台无限轮询（前台短周期、后台挂起，见 §6）。
- **不** 做全量 agent 会话控制（只读 trace + 终端，不注入路由规则）。

## 2. 模块布局（目录树）

```
magpie-ios/
├── project.yml                     # XcodeGen 配置（app target + 本地包引用）
├── App/
│   ├── Sources/
│   │   ├── MagpieApp.swift         # @main，TabView + scenePhase
│   │   ├── Views/
│   │   │   ├── Overview/           # 概览 Tab
│   │   │   ├── Activity/           # 动态 Tab（请求流水）
│   │   │   ├── Tmux/               # Tmux Tab（SwiftTerm）
│   │   │   ├── Agent/              # Agent Tab（实时路由/配额/统计）
│   │   │   ├── Services/           # 服务 Tab（docker/systemd）
│   │   │   └── Settings/           # Profile 编辑（sheet）
│   │   ├── Stores/                 # @Observable 状态（每 Tab 一个）
│   │   ├── Bridge/                 # SwiftTerm UIViewRepresentable、键盘附件
│   │   └── Support/                # 错误文案、格式化、Badge 等
│   └── Resources/                  # Assets.xcassets、Fixture JSON（开发用）
├── Packages/
│   ├── MagpieKit/                  # 纯 Swift：模型 + 网络 + 解析，Linux 可测
│   │   ├── Package.swift
│   │   ├── Sources/MagpieKit/
│   │   │   ├── Models/             # Codable 模型
│   │   │   ├── Networking/         # GatewayClient / WebClient / Transport
│   │   │   ├── LongPoll/           # trace 长轮询状态机
│   │   │   ├── Parsing/            # SSH 输出解析器（纯函数）
│   │   │   └── Config/             # Profile 模型（不含 Keychain）
│   │   └── Tests/MagpieKitTests/   # Linux 可运行
│   └── SSHKit/                     # macOS/iOS only（依赖 Citadel/SwiftNIO-SSH）
│       ├── Package.swift
│       └── Sources/SSHKit/
│           ├── SSHConnection.swift # actor 封装
│           ├── SSHCommandRunner.swift
│           └── SSHPTYChannel.swift # tmux attach 用
├── Fixtures/                       # Mock JSON（Ledger/Quota/Trace/路由）
├── .github/workflows/ci.yml
└── docs/
    ├── magpie-api-notes.md
    └── architecture.md
```

**包依赖原则**：`MagpieKit` 只依赖 Foundation（可选 URLSession），**绝不 import Citadel/SwiftNIO**。SSH 相关全部放 `SSHKit`，其平台限定为 iOS/macOS，因为 Citadel/SwiftNIO-SSH 在 Linux 上与 App 配置同构编译不可靠。

## 3. 配置与服务器 Profile

### Profile 字段
每个 Profile 对应一台 magpie 主机：

| 字段 | 存储位置 | 说明 |
|---|---|---|
| 名称 | UserDefaults/JSON | 显示用 |
| gateway URL | 明文 JSON | 形如 `http://<tailnet-host>:3425` |
| gateway key | Keychain | Bearer/x-api-key |
| web GUI URL | 明文 JSON | magpie web 端口 |
| runtime key | Keychain | cookie/`?key=` 用 |
| SSH host / port / user | 明文 JSON | 主机、端口、用户名 |
| SSH private key | Keychain | 私钥（ed25519/rsa）；或密码 |
| SSH host key fingerprint | Keychain（可选） | TOFU 钉扎，见 §7 |

- **明文 JSON**：存 `Library/Application Support/profiles.json`（通过 UserDefaults 或 FileManager），仅含非敏感信息。
- **Keychain**：所有密钥（gateway key、runtime key、SSH 私钥/密码、host fingerprint）经 `kSecClassGenericPassword` 存 Keychain，service 名按 `magpie-ios.<profileUUID>.<field>` 命名。
- Profile 模型在 MagpieKit 中只含非敏感字段 + 一个 `secretResolver` 抽象，Keychain 读取在 App 层实现，保证 MagpieKit 在 Linux 可测。

### Tailscale
- 直接使用 tailnet 主机名或 MagicDNS/IP 作为 host，无内置 VPN 逻辑。
- 提供可选按钮 deep-link 到 Tailscale App（`tailscale://`），仅尝试打开，失败则提示用户手动打开。

### UU Remote
- 可选“UU Remote”按钮，`UIApplication.open` `uuremote://`。UU Remote 仅在受控的 Windows/Mac 端可用，iOS 端未必能直接连接；按钮定位为“跳转到 UU Remote 客户端”，不做协议内自动化。
- 必须在 `Info.plist` 的 `LSApplicationQueriesSchemes` 声明 `tailscale` 与 `uuremote`，否则 `canOpenURL` 恒为 false。

## 4. 认证

### Gateway（Bearer）
- 所有 `/v1/magpie/*` 请求带 `Authorization: Bearer <gateway key>`（等价 `x-api-key`）。
- 401/403 时提示“检查 gateway key，或在 magpie 设置中开启 Share on local network”。非本机访问需开启共享且带 key，否则 403。

### Web GUI（Cookie）
- `/api/*` 由 runtime key 保护。magpie 打开 `?key=<KEY>` 链接会下发 cookie `magpie_web_<port>`（HttpOnly、SameSite=Lax、Path=/；固定 `MAGPIE_WEB_KEY` 时 MaxAge 400d，否则 session）。
- App 策略：存 runtime key 于 Keychain → 首次 `GET /api/hello`（或专用探活）带 `?key=` 或直接带 `Cookie: magpie_web_<port>=<key>` 请求头换取 cookie（URLSession 自动管理 cookie jar）→ 后续请求依赖 cookie。
- **key 轮换**：magpie 重启后 runtime key 变化 → 请求返回 401/403 → 清 cookie、用 Keychain 中 key 重新认证一次；若仍失败则提示用户在 web GUI 重新复制 key。
- cookie 名含端口，Profile 中 web 端口必须与 cookie 名一致；解析响应头时按 `magpie_web_<port>` 匹配。

## 5. 数据模型（Codable，容错解码）

所有模型用 `Codable`，并用容错解码策略：
- **未知字段**：直接忽略（Swift 默认）。
- **可选字段**：API 中大量 `?` 字段（如 `session_role?`、`priced`、`swapped`）一律 `T?`。
- **类型漂移**：`cost`/`total`/`seq` 可能是 number，用自定义 `LosslessStringConvertible` 或 `AnyDecodable` 包装，避免服务端改字符串导致整个解码失败。
- **日期**：API 时间字段格式不唯一。统一 `DateDecodingStrategy`：先 ISO8601，再常见变体（`yyyy-MM-dd'T'HH:mm:ssXXX`、带毫秒），最后回退为 `Date?` 且保留原始字符串（`rawTime: String?`）供展示。
- **行级容错**：Ledger/`rows`、`data[]`、`routes[]` 中单条解码失败不应拖垮整屏 → 解码时对数组做 per-element 容错（`try?` + 跳过并计数坏行）。

### 关键模型
```
GatewayHello   { name, version }
UsageSummary   { …same JSON as web /api/usage }
Ledger         { callerKeys:[Group], period, rows:[Row], offset, total, bucket, series:[SeriesPoint] }
Row            = Record + { session_role?, cost:Float, priced:Bool, swapped?, routed?, source?,
                            callerKeyLabel?, agentName, icon, providerName, access?, pricing_model?,
                            computerName? }
Record         { operation, route_id, t, agent, provider, host, providerKeyId, providerKeyName,
                 providerAccount, callerKeyId, callerKeyName, session_provider, session_account,
                 session_official_login, model, req, served, upstream, in, out, … }
Quota          { provider, name, kind, plan?, user?, windows:[QuotaSpan], balance?, balanceSplit?,
                 error?, asOf?, readDeferred?, readAt?, until? }
QuotaSpan      { name, used, remaining, resetsAt?, unlimited?, display?, amount?, limit?, unit?,
                 pool?, holds?, holdsWhy? }
QuotaCard      { …display cards }
Concurrency    { object:"concurrency", data:[Lane{busy,waiting,limit,…}], requests, waiting, tools, active }
TraceEnvelope  { seq, routes:[Route], totals:{requests,rerouted,errors}, mine:Bool, now }
Route          { seq,id,time,agent,parentSession?,session?,usage?[],kind?,model,effort?,tier?,
                 provider,group?,rule?,leadAccount?,subagent?,pinned?,order:[Weighed],…,priced }
```

5 小时与周配额：`Quota.windows` 里按 `name` 找到 5-hour / weekly 两个 `QuotaSpan`（每个有 `used/remaining/resetsAt`）。

## 6. 网络层

### 传输抽象
定义 `protocol HTTPTransport`（`send(_ request:) async throws -> (Data, HTTPURLResponse)`）：
- `LiveTransport`：URLSession 实现（默认 `URLSessionConfiguration.ephemeral`，cookie 手动管理或默认 jar）。
- `MockTransport`：读 Fixture JSON，按 URL 路径 + query 返回假数据（可注入延迟/错误）。
- 所有 Client 依赖协议，测试/截图替换实现。

### GatewayClient（MagpieKit）
- `GET /v1/magpie/usage?period=`、`/usage/requests?period=&offset=&limit=&filters`、`/quotas`、`/quotas/cards`、`/route?session=`、`/concurrency`、`/limit`、`/api/hello`。
- 统一注入 `Authorization: Bearer`。
- 超时：普通请求 15s；长轮询见下。

### WebClient（MagpieKit）
- `GET /api/gateway/trace?after=<seq>&wait=1`、`/api/gateway/history?day=`。
- 维护 cookie 认证状态机：`idle → needsAuth → authenticated`；401/403 → 触发 §4 重认证。

### 长轮询循环（trace）
状态机（纯逻辑，可在 Linux 测）：
```
init(after: 0)
loop:
  request trace?after=lastSeq&wait=1   // 服务端最长等 25s
  on .success(env): lastSeq = env.seq; yield routes; loop
  on .timeout/.empty: backoff(delay); loop
  on .unauthorized: reAuth(); backoff; loop
  on .networkError: exponentialBackoff(0.5s→30s, jitter); loop
  on .cancelled: exit
```
- **超时**：请求 `timeoutInterval` 设 **35s**（> 服务端 25s），避免误判超时。
- **取消**：循环绑定到一个 `Task`；Tab 离开（`onDisappear`）或 `scenePhase != .active` 时 `task.cancel()`。`URLSession` 长轮询在取消时立即释放连接。
- **scenePhase 暂停**：App 进入 `.background` → 取消所有长轮询与 SSH 轮询；`.active` → 恢复（重建 Task）。概览/动态采用前台短轮询（如 10–30s），后台一律停止，**不** 用后台 fetch 做长轮询。
- **backoff**：指数退避 + 全抖动；401/403 不重试业务重试而是先重认证。

### 动态 Tab 分页
`/usage/requests?offset=&limit=` 返回 `offset/total`，列表滚动到底加载下一页；`bucket/series` 用于顶部趋势图（占位，见 dataviz 原则——数据驱动，不硬编码）。

## 7. SSH 层（SSHKit，iOS/macOS only）

### 连接 Actor
```
actor SSHConnection {
  func connect(profile) throws          // Citadel SSHClient.connect
  func run(_ cmd: String) async throws -> SSHCommandOutput
  func openPTY(rows:cols:) async throws -> PTYHandle
  func disconnect()
}
```
- 认证：`.ed25519` / `.rsa`（私钥来自 Keychain）/ `.password`。
- **Host key TOFU**：首次连接记录 `hostKeyValidator` 返回的 fingerprint 到 Keychain；之后每次校验，不一致则**拒绝连接**并提示“主机指纹变化，可能存在中间人/主机重装”，允许用户在确认后重置。用户可在 Settings 查看/清除已钉扎指纹。
- **重连**：命令执行失败（连接断开）→ 幂等命令最多重试 1 次（重新 connect 后重发）；有状态 PTY 不自动重连，提示用户手动重连。

### 命令执行（服务 Tab / 概览采集）
- 只读采集命令（概览）：
  - 端口：`ss -tlnp`（或 `netstat -tlnp` fallback）
  - 容器：`docker ps --format '{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}'`
  - systemd：`systemctl list-units --type=service --no-pager --plain --no-legend`
  - 进程：`ps -eo pid,ppid,comm,args --no-headers`
- 服务启停命令（服务 Tab，带确认弹窗）：
  - docker：`docker start <name>` / `docker stop <name>`
  - systemd：`systemctl start <unit>` / `systemctl stop <unit>`（stop 前可先 `systemctl is-active` 展示当前态）
- 所有命令输出经 MagpieKit 纯函数解析器（`ss` 行 → `Port`、`docker ps` → `Container`、`systemctl` → `Unit`、`ps` → `Process`），**解析器无 Citadel 依赖，Linux 可测**。

### PTY（Tmux Tab）
- `tmux attach -t <session>` 或 `tmux new -s magpie`（无会话时）。
- `withPTY`/`withTTY` 建立 PTY channel，`PTYHandle` 暴露 `send(bytes)` 与 `resize(rows:cols:)`（对应 `SSHPTYChannel`）。
- 终端尺寸变化由 SwiftTerm delegate 回调驱动 resize。

## 8. 终端桥接（App 层）

- `TerminalView`：`UIViewRepresentable` 包装 SwiftTerm `TerminalView`（UIKit），喂字节用 `feed(byteArray:)`。
- 数据通路：SSH PTY `receive` → `[UInt8]` → `TerminalView.feed`；SwiftTerm `send(data:)` delegate → `PTYHandle.send`。
- **resize**：SwiftTerm `sizeChanged` → `PTYHandle.resize(rows:cols:)`。
- **键盘附件键**：`inputAccessoryView` 提供 Esc / Tab / Ctrl / ↑↓←→ / `-`/`|`/`/` 等，便于在 iOS 软键盘输入 tmux 常用键。
- 连接状态条：连接中/已连接/断开/重连按钮；断开时清空缓冲区可选。

## 9. 状态管理（@Observable）

每 Tab 一个 store，均 `@MainActor @Observable`：

| Store | 依赖 | 状态 |
|---|---|---|
| `OverviewStore` | GatewayClient + SSHConnection | services/ports/processes 快照、5h/周配额、刷新中、错误 |
| `ActivityStore` | GatewayClient | Ledger 行、分页 offset/total、趋势 series、筛选 |
| `TmuxStore` | SSHConnection | 连接状态、会话列表（`tmux ls`）、PTY 句柄 |
| `AgentStore` | WebClient + GatewayClient | trace 路由流、concurrency、quota cards、长轮询 Task |
| `ServicesStore` | SSHConnection | 容器/单元列表、启停状态、待确认操作 |
| `AppState` | 全局 | 当前 Profile、`isMockMode`、scenePhase、全局错误总线 |

- Store 之间不共享可变引用，通过 `AppState` 传递当前 Profile 与依赖注入的 client 工厂。
- 刷新用 `Task` 持有；`deinit`/`onDisappear` 时 `cancel`。

## 10. 错误处理

- 定义 `MagpieError`（typed）：`.badStatus(code)`、`.unauthorized`、`.network(underlying)`、`.sshHostKeyChanged`、`.sshAuthFailed`、`.decoding(badRows:Int)`、`.timeout`。
- 用户可读文案集中在 `Support/ErrorMessages.swift`，按错误类型映射中文提示：
  - 403 → “未开启 Share on local network 或 key 错误”。
  - 401 web → “runtime key 失效，请重新获取”。
  - SSH 认证失败 → “检查私钥/密码与主机用户”。
  - host key 变化 → “主机指纹变化，请确认后重连”。
- 日志 **绝不** 输出 key、私钥、cookie 值；只记 profile 名、endpoint、状态码、耗时。敏感字段在打印前统一脱敏（`redacted`）。

## 11. 安全

- **ATS（App Transport Security）**：magpie 在 tailnet 上通常走 `http://`（非 TLS）。两种方案：
  - `NSAllowsArbitraryLoads = true`：简单，但全局放开 http，最不推荐。
  - **异常域（推荐）**：`NSExceptionDomains` 对 `*.ts.net` / 用户自定义 tailnet 域启用 `NSExceptionAllowsInsecureHTTPLoads`，其余域保持默认安全。
  - 折衷：若用户 host 为 IP 且不可枚举，需在异常域中使用具体 IP/域名；文档应说明此 trade-off，避免无脑 `NSAllowsArbitraryLoads`。
- 密钥只进 Keychain，不进 UserDefaults、不进日志、不进截图（Mock 模式演示无真实密钥）。
- 私钥在内存中不持久化缓存；SSH 连接断开即释放。

## 12. Mock 数据模式

- `AppState.isMockMode` 开关（设置页 + 首屏无 Profile 时自动建议开启）。
- 开启后所有 client 走 `MockTransport`，读取 `Fixtures/*.json`（Ledger/Quota/Trace/Concurrency/容器列表等），数据源切换为 `protocol` 实现（Live/Mock），UI 无感知。
- 全程顶部/角标显示 **“Mock data”** 徽章，防止误当真实数据。
- Mock 数据不触网、不连接 SSH（Tmux Tab 在 Mock 模式禁用或提供静态演示）。

## 13. 工程生成与构建

- 无提交的 `.xcodeproj`；`project.yml` 声明 app target（iOS 17+）与本地包引用：
  ```yaml
  name: magpie-ios
  packages:
    MagpieKit: { path: Packages/MagpieKit }
    SSHKit:    { path: Packages/SSHKit }
  targets:
    magpie-ios:
      type: application
      platform: iOS
      deploymentTarget: "17.0"
      sources: [App/Sources, App/Resources]
      dependencies:
        - package: MagpieKit
        - package: SSHKit
      info:
        path: App/Info.plist
        properties:
          LSApplicationQueriesSchemes: [tailscale, uuremote]
          NSAppTransportSecurity: { ... }   # 异常域策略
  ```
- 生成：`xcodegen generate`（CI 与本地均执行）。

## 14. CI/CD（GitHub Actions）

`.github/workflows/ci.yml`：

**macos job（构建 + IPA）**
1. `brew install xcodegen`
2. `xcodegen generate`
3. `xcodebuild build -project magpie-ios.xcodeproj -scheme magpie-ios -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
4. 组装 `Payload/magpie-ios.app` → `zip -r magpie-ios.ipa Payload`
5. `actions/upload-artifact` 上传 `.ipa`。

**Linux job（MagpieKit 测试）**
- `swift test --package-path Packages/MagpieKit`（无 Citadel，纯 Foundation 可跑）。
- 备注：`SSHKit` 不在 Linux 测（Citadel/SwiftNIO-SSH 平台限制），仅 macos CI 上做 SSHKit 集成测试（可选、需 mock SSH server）。

无签名配置；用户自行签名（轻松签/LCSign）。

## 15. 测试策略

### Linux `swift test`（MagpieKit，必须全绿）
- 模型解码 Fixture（Ledger/Quota/Trace/Route，含未知字段、可选字段、坏行容错）。
- 请求构造（URL/query/header 拼装，Bearer、Cookie 名 `magpie_web_<port>`）。
- 长轮询状态机（用 `MockTransport` 注入 seq 推进、超时、401、网络错误 → 断言 backoff/重认证/取消）。
- SSH 输出解析器（`ss`/`docker ps`/`systemctl`/`ps` 样本 → 结构体）。

### 仅 macOS CI / 真机
- UI（Snapshot/手动）、SwiftTerm 桥接、SSHKit 集成（Citadel 连本地 mock sshd）、Keychain 读写、IPA 构建。

## 16. 任务分解（T1..Tn）

每条含可观察验收标准（命令/输出）。

- **T1 工程骨架** — `project.yml` + 空 app + MagpieKit/SSHKit 包。
  验收：`xcodegen generate` 成功；`xcodebuild build … CODE_SIGNING_ALLOWED=NO` 通过；`swift test --package-path Packages/MagpieKit` 通过（占位测试）。
- **T2 配置层** — Profile 模型 + JSON 存储 + Keychain（App 层）。
  验收：新增/删除/切换 Profile；重启后 Profile 与密钥仍在（Keychain 持久）。
- **T3 MagpieKit 模型** — §5 全部模型 + 容错解码。
  验收：`swift test` 模型 Fixture 全绿（含坏行/未知字段/类型漂移用例）。
- **T4 传输抽象 + MockTransport + Mock 徽章**。
  验收：打开 Mock 模式，各 Tab 显示 Fixture 数据，顶部有 “Mock data” 徽章。
- **T5 GatewayClient** — usage/requests/quotas/cards/route/concurrency/limit/hello。
  验收：单测断言 URL/header/query；真机连测试实例能拉到数据。
- **T6 概览 Tab** — SSH 采集 + 配额卡片。
  验收：展示端口/容器/systemd/进程 + 5h/周配额；SSH 断开显示错误并可重试。
- **T7 WebClient + cookie 认证** — hello 探活、cookie 获取、401/403 重认证。
  验收：首次连接成功换 cookie；手动改 key 后重认证流程生效；单测覆盖 401→reAuth 状态迁移。
- **T8 动态 Tab** — Ledger 分页 + 趋势。
  验收：列表滚动加载下一页；筛选参数正确；offset/total 边界处理。
- **T9 Agent Tab 长轮询** — trace 循环 + 取消 + backoff。
  验收：`swift test` 状态机用例全绿；真机切 Tab 后台时请求被取消（无泄漏连接）。
- **T10 Agent Tab 统计** — concurrency/route/quotas/cards 汇总。
  验收：路由列表、并发 lane、配额卡渲染。
- **T11 SSHKit** — 连接 actor + 命令执行 + TOFU 钉扎 + 重连。
  验收：真机连 tailnet 主机执行 `docker ps`/`systemctl` 成功；改主机指纹被拒并提示。
- **T12 服务 Tab** — 容器/单元启停 + 确认弹窗。
  验收：启动/停止前有确认；操作后状态刷新；错误文案正确。
- **T13 Tmux Tab** — SwiftTerm + PTY + resize + 键盘附件。
  验收：`tmux attach` 可交互；旋转/键盘弹出触发 resize；Esc/Ctrl 等附件键可用。
- **T14 Tailscale/UU Remote 深链 + ATS 异常域**。
  验收：`LSApplicationQueriesSchemes` 声明；点击深链；http 走异常域不被 ATS 拦截。
- **T15 错误处理与脱敏**。
  验收：所有错误路径有中文文案；日志无密钥/cookie 值。
- **T16 CI** — macos 构建/打包 IPA + Linux swift test。
  验收：PR 出 `magpie-ios.ipa` artifact；Linux job 全绿。
- **T17 收尾文档** — README（签名说明、ATS 说明、Mock 说明）。

## 17. 不要做的事（NOT to do）
- **不** 运行/部署/重启/写配置 magpie 网关本身（只读监控 + 容器/服务启停）。
- **不** 提交 `.xcodeproj`；不提交任何密钥/私钥/真实 Profile JSON。
- **不** 在后台做长轮询或高频轮询；后台一律挂起。
- **不** 复制 vibebuddy 代码。
- **不** 使用全局 `NSAllowsArbitraryLoads` 除非用户明确选择；默认用异常域。
- **不** 把 Citadel 引入 MagpieKit；SSH 只存在于 SSHKit。
- **不** 在日志/截图/测试 Fixture 中放真实凭据。

## 18. 风险
- **长轮询超时**：URLSession 超时必须 >25s（35s），否则 trace 空转误判。
- **runtime key 轮换**：magpie 重启后 web key 变化，需可靠重认证，否则 Agent Tab 静默失效。
- **Citadel Linux 兼容**：已通过拆分 SSHKit 规避，代价是 SSH 逻辑无法在 Linux 单测，靠解析器纯函数 + macos 集成测试覆盖。
- **SSH 输出格式漂移**：`ss`/`docker ps`/`systemctl` 跨发行版/版本输出不同，解析器要容忍列数变化与缺失字段。
- **ATS 与 http**：tailnet 非 TLS 依赖异常域；用户 host 多变时配置成本高。
- **TOFU 误报**：主机重装/重建容器导致指纹变化属正常，需清晰的重置 UI，避免用户误以为被攻击。

## 19. 待用户决策
1. 概览/动态的前台轮询间隔（建议 15–30s；是否需可配置）。
2. 是否内置 `MAGPIE_WEB_KEY` 固定时的“记住 cookie”行为（与 session cookie 的差异提示）。
3. ATS 策略：异常域 vs 全局放开（给出默认推荐：异常域 + 用户可添加 host）。
4. SSH 私钥格式范围（是否只支持 ed25519/rsa，是否支持加密私钥口令）。
5. 是否需要在概览 Tab 增加 gateway `/v1/magpie/limit` 的显式展示。
6. UU Remote 按钮目标语义（仅跳转 App vs 打开具体受控端，后者需更多 URL 参数信息）。
7. Mock Fixture 是否提交仓库（建议提交脱敏示例，便于截图与 CI）。
