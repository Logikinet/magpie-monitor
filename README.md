**中文** | [English](README.en.md)

# magpie-monitor

magpie-monitor 是面向 [yetone/magpie](https://github.com/yetone/magpie) LLM 网关的非官方监控仓库，包含原生 iOS 应用、Web 仪表盘，以及可选的 Go collector。iOS 与 Web 查看网关状态、请求活动和 Agent；collector 为主机、服务和 Tmux 提供只读数据。本页的截图、GIF 和 MP4 全部使用模拟数据。

## 演示

模拟数据。点击预览播放对应的 MP4。

| Web | iOS |
| --- | --- |
| [![Web 演示（模拟数据）](docs/media/web-demo.gif)](docs/media/web-demo.mp4) | [![iOS 演示（模拟数据）](docs/media/ios-demo.gif)](docs/media/ios-demo.mp4) |

[Web MP4](docs/media/web-demo.mp4) · [iOS MP4](docs/media/ios-demo.mp4)

## 功能

### 概览

网关版本、今日请求与 token、并发、配额摘要和限额。配置 collector 后，同时显示主机负载、CPU、内存和磁盘。

### 活动

网关请求流水与趋势。collector 另外提供本机 Git 提交，只读本地仓库。

### Tmux

会话列表与窗格预览。iOS 可通过 SSH，用 SwiftTerm 附着到会话。Web 显示 collector 采集的终端文本。

### Agent

- **实时路由**：Live 模式通过 Web GUI 的全局 trace 跟随当前请求。直连模式按会话查看 `/v1/magpie/route`。
- **用量与配额**：今日、7 天、30 天与全部用量，以及配额卡片。
- **服务商**：展示网关返回的服务商，凭据在展示前去掉。
- **运行时**：本机已安装的 Agent CLI、进程与会话计数。collector 不读取会话正文。

### 服务

监听端口、Docker 发布端口和 systemd 单元。iOS 可通过 SSH 启动或停止服务。collector 默认关闭写操作。

### Collector

Go 1.22+ 只读采集服务，默认监听 `127.0.0.1:8787`。提供主机、服务、Tmux、运行时、任务、活动、仓库和 Tailscale 状态。配置读取密钥后，每个 GET 都要带 `X-Collector-Key`。

### 语言

iOS 与 Web 支持简体中文、English、日本語。Web 外观可以跟随系统，或固定浅色、深色；iOS 跟随系统。两端都有模拟数据模式。

## 截图

模拟数据。

### Web

|  | 概览 | 动态 | Tmux | Agent | 服务 |
| --- | --- | --- | --- | --- | --- |
| 桌面深色 | <img src="web/docs/screenshots/overview-desktop-dark.png" width="220" alt="Web 概览，桌面深色（模拟数据）"> | <img src="web/docs/screenshots/activity-desktop-dark.png" width="220" alt="Web 动态，桌面深色（模拟数据）"> | <img src="web/docs/screenshots/tmux-desktop-dark.png" width="220" alt="Web Tmux，桌面深色（模拟数据）"> | <img src="web/docs/screenshots/agent-desktop-dark.png" width="220" alt="Web Agent 实时路由，桌面深色（模拟数据）"> | <img src="web/docs/screenshots/svc-desktop-dark.png" width="220" alt="Web 服务，桌面深色（模拟数据）"> |
| 移动端 | <img src="web/docs/screenshots/overview-mobile-dark.png" width="140" alt="Web 概览，移动端深色（模拟数据）"> | <img src="web/docs/screenshots/activity-mobile-dark.png" width="140" alt="Web 动态，移动端深色（模拟数据）"> | <img src="web/docs/screenshots/tmux-mobile-dark.png" width="140" alt="Web Tmux，移动端深色（模拟数据）"> | <img src="web/docs/screenshots/agent-mobile-dark.png" width="140" alt="Web Agent，移动端深色（模拟数据）"> | <img src="web/docs/screenshots/svc-mobile-dark.png" width="140" alt="Web 服务，移动端深色（模拟数据）"> |

### iOS

| 概览 | 动态 | Tmux | Agent | 服务 |
| --- | --- | --- | --- | --- |
| <img src="ios/docs/screenshots/mock-overview.png" width="160" alt="iOS 概览（模拟数据）"> | <img src="ios/docs/screenshots/mock-activity.png" width="160" alt="iOS 动态（模拟数据）"> | <img src="ios/docs/screenshots/mock-tmux.png" width="160" alt="iOS Tmux（模拟数据）"> | <img src="ios/docs/screenshots/mock-agent.png" width="160" alt="iOS Agent（模拟数据）"> | <img src="ios/docs/screenshots/mock-services.png" width="160" alt="iOS 服务（模拟数据）"> |

## 架构

```text
iOS 应用  ---+--> magpie 网关        默认 127.0.0.1:3425
             |
Web 仪表盘 --+--> magpie Web GUI     runtime key
             |
             +--> collector          默认 127.0.0.1:8787，只读

Web Live（可选）

浏览器 --> Cloudflare Worker（只读路径白名单，仅 GET / HEAD）
              |--> Cloudflare Tunnel / Access（可选）
              |--> 回环上的网关与 Web GUI
              +--> collector

Tailscale（可选）

iPhone --> <your-host>
```

Worker 只转发白名单中的只读路径。走 Tunnel 或 Workers VPC 时，网关绑定 `MAGPIE_ADDR=127.0.0.1:<port>`，并保持未设置 `MAGPIE_TRUST_PROXY`。手机与跑 magpie 的机器可以同在 Tailscale 上，主机名用 MagicDNS，例如 `devbox.example.ts.net`。

## 快速开始

### Web 模拟数据

```sh
cd web
npm ci
npm run dev
```

打开终端里打印的 Vite 地址，加上 `/?mock=1`。模拟模式使用脱敏 fixture，不连接真实上游。

### Collector

```sh
cd collector
go build -o magpie-collector ./cmd/magpie-collector
./magpie-collector
```

默认只监听本机，写操作关闭。在另一个终端：

```sh
curl http://127.0.0.1:8787/v1/collector/hello
```

配置了读取密钥时加上 `-H "X-Collector-Key: <collector-read-key>"`。

### iOS

在 GitHub Actions 打开名为 CI 的工作流，对目标分支执行 **Run workflow**（`workflow_dispatch`），或推送改动 `ios/**` 的提交。在该次运行的 Artifacts 下载未签名包 `magpie-ios-ipa`，用轻松签（Esign）或 LCSign 签名后再安装。证书与分发由你自己负责。要求 iOS 17+。每个 Profile 填写自己的地址和密钥，例如网关 `https://<your-host>:3425`。

在 macOS 上自行构建：

```sh
cd ios
xcodegen generate
open magpie-ios.xcodeproj
```

## 文档

- [部署与排障](docs/DEPLOY.md)
- [本地开发](docs/dev-run.md)
- [Collector API](docs/collector-api.md)

组件说明：[iOS](ios/README.md) · [Web](web/README.md) · [Collector](collector/README.md)。

## CI

工作流 [.github/workflows/ci.yml](.github/workflows/ci.yml) 在推送到 `main`、pull request，以及手动 `workflow_dispatch` 时运行。按路径筛选 `ios/**`、`web/**`、`collector/**`（工作流文件本身也会触发对应任务）。手动运行会执行全部任务。

| 任务 | 何时运行 | 结果 |
| --- | --- | --- |
| `linux-test` | iOS 改动，或手动 | `swift test`（MagpieKit、SSHKit） |
| `ios-build` | iOS 改动，或手动 | 未签名 IPA，产物 `magpie-ios-ipa` |
| `screenshots` | `main` 上的 iOS 推送，或手动 | 产物 `mock-screenshots` |
| `ios-demo` | 仅手动 | 产物 `ios-demo-media`（`ios-demo.mp4`、`ios-demo.gif`） |
| `web` | Web 改动，或手动 | `npm test`、`npm run build` |
| `web-screenshots` | `main` 上的 Web 推送，或手动 | 产物 `web-mock-screenshots` |
| `collector` | collector 改动，或手动 | `go vet`、`go test`；不上传二进制 |

## 部署备注

客户端没有内置服务商列表。配额、路由和并发都显示 magpie 网关返回的内容，因此在 magpie 里增删 provider 不用改客户端。

可以在跑 magpie 的同一台机器上安装 [oh-my-free-models](https://github.com/hakilee/oh-my-free-models)：

```sh
npm i -g oh-my-free-models
```

它默认听 `http://localhost:4567`，只应绑在本机或私有网络。在 magpie 里把它配成某个路由组的第一个自定义 provider，DeepSeek 官方 API 作为 fallback。Claude Code 走该代理的 `/anthropic` 路径。密钥放在 `~/.oh-my-free-models/.env`，不要写进本仓库或 App，也不要使用来路不明的公共中转。

## 许可证

本仓库采用 [MIT 许可证](LICENSE)。第三方声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)：yetone/magpie 路由插件（MIT，copyright (c) 2026 yetone）、SwiftTerm、Citadel，以及 SwiftNIO、swift-nio-ssh、swift-crypto（Apache-2.0）、Preact 和 Vite。
