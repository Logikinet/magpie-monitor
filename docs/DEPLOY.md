# 部署运行手册

magpie-monitor 是面向 [yetone/magpie](https://github.com/yetone/magpie) 网关的非官方监控仓库，包含 `ios/`、`web/`、`collector/`。本文只写本仓库里已经存在的命令、标志、环境变量、路径和 CI 产物名。域名、登录方式和密钥用占位符：`<your-host>`、`<your-domain>`、`<collector-read-key>`、`<gateway-key>`、`<web-key>`。文档里的 `magpie.example.com`、`collector.example.com`、`devbox.example.ts.net` 都是占位名。

相关文档：[本地开发](dev-run.md) · [Collector API](collector-api.md) · [Collector 说明](../collector/README.md) · [Web 说明](../web/README.md) · [iOS 说明](../ios/README.md)。

## 快速检查清单

- [ ] 已用 `git clone` 取得本仓库。magpie 网关按上游文档另装，不在本仓库里。
- [ ] 网关已开启 **Share on local network**，并设置了 gateway key。
- [ ] 已设置固定的 `MAGPIE_WEB_KEY`。没有设置 `MAGPIE_TRUST_PROXY`。
- [ ] 若 Web 走 Cloudflare Tunnel / Workers VPC，网关绑定 `MAGPIE_ADDR=127.0.0.1:<port>`。
- [ ] collector 已构建，默认只听 `127.0.0.1:8787`，读取密钥已配置，写操作仍关闭。
- [ ] 需要写操作时：`allow_actions` 与动作密钥同时打开，且 `units` 里有精确允许项。
- [ ] （可选）Web 已 `npm run build`，`web/wrangler.jsonc` 的占位符已换成自己的值，`COLLECTOR_KEY` 用 wrangler secret，域名放在 Cloudflare Access 后面。
- [ ] iOS 使用未签名产物 `magpie-ios-ipa`，或自己构建；用轻松签 / LCSign 签名后再装。
- [ ] 每个 Profile 都填了自己的地址和密钥。HTTP 可以连，界面会标成不安全。
- [ ] 用下面的 `curl` 看过 collector `/v1/collector/hello`、magpie `/api/gateway/trace?after=0`、网关 `/v1/magpie/limit`。

## 1. 部署概览

克隆本仓库就能拿到三份源码。能跑起来还要各自的工具链，magpie 网关本身也不在这个仓库里。

| 部分 | 仓库里有什么 | 还要自己准备 |
| --- | --- | --- |
| magpie 网关 | 没有安装脚本 | 按上游仓库文档安装与配置 |
| collector | Go 1.22 源码，`collector/deploy/magpie-collector.service` | Go 1.22+（CI 用 `1.22.x`） |
| web | Preact + Vite 前端，`web/worker/`，`web/wrangler.jsonc` | Node 22 与 npm（CI 的 `node-version` 是 `22`）。部署是步骤说明，不是本仓库已完成的发布 |
| iOS | SwiftUI 工程，`ios/project.yml` | macOS、Xcode、XcodeGen；系统 iOS 17+。CI 产物是未签名 IPA |

三端可以分开装。只看模拟界面时，不必先有真实网关：Web 用 `/?mock=1`，iOS 打开「模拟数据模式」。

### 1.1 magpie 服务端

安装、升级和数据目录以 [yetone/magpie](https://github.com/yetone/magpie) 的文档为准。本仓库不复制它的安装命令。

和监控端有关、并且已经写在本仓库里的运行约束：

- 网关默认 `127.0.0.1:3425`（设置里的 Gateway port）。Web GUI 是另一个端口。
- 非本机访问要开启 **Share on local network**，并且带上 gateway key，否则返回 403。
- 开启共享后，上游默认会改听 `0.0.0.0`。给 Tunnel / Workers VPC 用时，设置 `MAGPIE_ADDR=127.0.0.1:<port>`，让它继续只听回环，同时仍然按远程请求校验 key。
- Web GUI 的 `/api/*` 用 runtime key。用带 `?k=<web-key>` 的链接打开一次，会写下 cookie `magpie_web_<port>`。
- 把 `MAGPIE_WEB_KEY` 设成固定值，重启后 key 才不变。固定时 cookie MaxAge 为 400 天，否则是会话 cookie。
- 不要设置 `MAGPIE_TRUST_PROXY`，也不要设成 `MAGPIE_TRUST_PROXY=1`。

给面板单独用一把只读用途的 gateway key。被预算、模型或账号限制住的 held key 只能看到自己的行，`/v1/magpie/usage` 汇总会被拒绝。

### 1.2 collector

在家中服务器上构建并以前台用户运行。默认只听本机，写操作关闭。

```sh
cd collector
go build -o magpie-collector ./cmd/magpie-collector
./magpie-collector
```

可选 JSON 配置。环境变量覆盖文件里的同名字段。未知 JSON 键、非法布尔环境变量都会让进程在启动时退出。

```sh
./magpie-collector -config config.json
```

非回环地址还必须同时加上 `-allow-remote`，并且配置了非空读取密钥。`127.0.0.1` 和 `::1` 算回环。主机名 `localhost` 不算，只写 `localhost:8787` 会启动失败。

```sh
./magpie-collector -config config.json -allow-remote
```

#### 环境变量

| 环境变量 | 默认 | 作用 |
| --- | --- | --- |
| `MAGPIE_COLLECTOR_ADDR` | `127.0.0.1:8787` | 监听地址 |
| `MAGPIE_COLLECTOR_KEY` | 空 | 读取密钥。非空时每个 GET 都要带 `X-Collector-Key` |
| `MAGPIE_COLLECTOR_ACTION_KEY` | 空 | 写操作密钥，和读取密钥分开 |
| `MAGPIE_COLLECTOR_ALLOW_ACTIONS` | `false` | 为 `true` 才允许考虑写操作 |
| `MAGPIE_COLLECTOR_EXPOSE_CMDLINE` | `false` | 为 `true` 时才返回脱敏后的 cwd / cmdline |
| `MAGPIE_COLLECTOR_REPOS` | 空 | 仓库根目录。Linux / macOS 用 `:` 分隔 |
| `MAGPIE_WEB_URL` | 空 | magpie Web GUI 的 base URL，只接受 http 或 https，不能带用户信息、查询串或片段 |
| `MAGPIE_WEB_KEY` | 空 | collector 访问 Web GUI 时使用的 runtime key，只放在服务端 cookie 里 |

布尔值用 `true` / `false`（Go 的 `ParseBool` 也接受 `1` / `0`）。写错就启动失败。

只存在于 JSON、没有对应环境变量的字段：

| JSON 键 | 默认 | 作用 |
| --- | --- | --- |
| `units` | 空数组 | 允许操作的单元，必须是精确的 `user:<name>.service` 或 `system:<name>.service` |
| `audit_log` | `collector-audit.jsonl` | 相对当前工作目录。建议写成绝对路径 |

对应的 JSON 键还有 `addr`、`key`、`action_key`、`allow_actions`、`expose_cmdline`、`repos`、`magpie_web_url`、`magpie_web_key`。配置文件和环境文件用模式 `0600`。

写操作要同时满足：`allow_actions` 为 true，且 `action_key` 非空。之后 POST 的 `X-Collector-Key` 必须是动作密钥。读取密钥不能写。即使用回环也要带动作密钥。带 `Origin` 的浏览器请求会被 403 拒绝。单元不在 `units` 里会拒绝。动作在执行前必须先追加审计日志，文件模式 `0600`；这一步写失败就不会执行。

`hello` 在可写时才会把这些名字放进 `caps`：`actions/svc-pause`、`actions/svc-resume`、`actions/unit-start`、`actions/unit-stop`、`actions/tmux-send`、`actions/tmux-kill`、`actions/tmux-new`、`actions/tmux-wake`、`actions/task-run`、`actions/quota-refresh`。

#### systemd 用户单元

示例文件：[collector/deploy/magpie-collector.service](../collector/deploy/magpie-collector.service)。它是 user unit：`ExecStart` 使用 `%h/.local/bin/magpie-collector -config %h/.config/magpie-collector/config.json`，可选环境文件 `%h/.config/magpie-collector/environment`（路径前的 `-` 表示文件可以不存在），工作目录 `%h/.local/state/magpie-collector`，`StateDirectory=magpie-collector`，`WantedBy=default.target`。单元还设置了 `UMask=0077`、`NoNewPrivileges=true`、`PrivateTmp=true`、`Restart=on-failure`、`RestartSec=5`。

按这个文件安装：

```sh
cd collector
go build -o magpie-collector ./cmd/magpie-collector
mkdir -p "$HOME/.local/bin" "$HOME/.config/magpie-collector" "$HOME/.config/systemd/user"
cp magpie-collector "$HOME/.local/bin/magpie-collector"
```

`$HOME/.config/magpie-collector/config.json` 示例（密钥放环境文件，不放进这个文件）：

```json
{
  "addr": "127.0.0.1:8787",
  "allow_actions": false,
  "repos": ["<repo-root>"],
  "magpie_web_url": "http://127.0.0.1:<web-port>",
  "units": ["user:<name>.service"],
  "audit_log": "collector-audit.jsonl"
}
```

`$HOME/.config/magpie-collector/environment` 示例：

```sh
MAGPIE_COLLECTOR_KEY=<collector-read-key>
MAGPIE_WEB_KEY=<web-key>
```

```sh
chmod 0600 "$HOME/.config/magpie-collector/config.json" "$HOME/.config/magpie-collector/environment"
cp deploy/magpie-collector.service "$HOME/.config/systemd/user/magpie-collector.service"
systemctl --user daemon-reload
systemctl --user enable --now magpie-collector.service
```

这是用户会话里的单元。该用户没有 systemd 用户会话时，单元不会自己起来。

默认审计日志因此落在 `$HOME/.local/state/magpie-collector/collector-audit.jsonl`（工作目录下的 `collector-audit.jsonl`）。JSON 里把 `audit_log` 写成绝对路径就会改到别处。日志行是 JSON，字段为 `at`、`action`、`status`，不含密钥正文。

确认：

```sh
curl -sS -H "X-Collector-Key: <collector-read-key>" http://127.0.0.1:8787/v1/collector/hello
curl -sS -H "X-Collector-Key: <collector-read-key>" http://127.0.0.1:8787/v1/collector/sys
```

没有配置读取密钥时可以不带这个头。配置了以后，缺头或密钥错误返回 401，正文是 `read token required`。

HTTP 本身不加密。要给手机或 Worker 用时，放在 Tailscale、SSH 或 Cloudflare Tunnel 后面，不要把未加密端口直接暴露到公网。collector 不发送 CORS 头。

CI 的 `collector` job 只跑 `go vet ./...` 和 `go test ./...`，不上传二进制产物。

### 1.3 web

Web 可以只在本机看模拟数据，不必部署：

```sh
cd web
npm ci
npm run dev
```

打开终端里打印的 Vite 地址，加上 `/?mock=1`。`web/README.md` 里的本地地址是 `http://localhost:5173/?mock=1`。`npm test` 跑 Vitest。`npm run build` 会先 `npm run typecheck`，再把静态文件写到 `web/dist`。

生产形态是同一源上的静态页面加 Cloudflare Worker。仓库把部署标成尚未完成，下面是按现有模板操作的步骤，不是已经替你执行过的发布。

1. 在 Cloudflare 上准备 Tunnel 或 Workers VPC，让 Worker 能访问家里只听回环的 magpie。网关不要有公网主机名。
2. 编辑 [web/wrangler.jsonc](../web/wrangler.jsonc)。`assets.directory` 是 `./dist`，所以先构建。`run_worker_first` 只抢先处理 `/proxy/*` 和 `/v1/collector/*`，其余走静态资源。
3. 把 `vpc_services` 里的占位符换成自己的 service id：
   - 绑定 `MAGPIE_GATEWAY`，`service_id` 现为 `<YOUR_GATEWAY_VPC_SERVICE_ID>`
   - 绑定 `MAGPIE_WEB`，`service_id` 现为 `<YOUR_WEB_VPC_SERVICE_ID>`
4. 改 `vars`（不要把密钥写进 `vars`）：

   | 变量 | 模板里的值 | 含义 |
   | --- | --- | --- |
   | `COLLECTOR_URL` | `https://collector.example.com` | Worker 去拉 collector 的源。必须是 Worker 能够访问的 http(s) URL，不能带用户名、查询串或片段 |
   | `ACCESS_TEAM_DOMAIN` | `<team>.cloudflareaccess.com` | Access 团队域，须匹配 `*.cloudflareaccess.com` |
   | `ACCESS_AUD` | `<ACCESS_AUD_TAG>` | 该 Access 应用的 AUD |
   | `GATEWAY_ORIGIN` | `http://127.0.0.1:3425` | VPC 绑定 `fetch` 用的网关源，端口要和网关实际监听一致 |
   | `WEB_ORIGIN` | `http://127.0.0.1:3426` | Web GUI 源。`3426` 只是模板示例 |
   | `WEB_PORT` | `3426` | 用来拼 cookie 名 `magpie_web_<port>`，必须是 Web GUI 的真实端口 |

   `ACCESS_DISABLED=true` 只在请求主机名是 `localhost` 或 `127.0.0.1` 时跳过 Access 校验，不能用来放开 `<your-domain>`。

5. `COLLECTOR_KEY` 用 wrangler secret 写入，对应 Worker 环境里的 `COLLECTOR_KEY`。这是 collector 的读取密钥。不要写进 `wrangler.jsonc`。
6. 给自定义域名建 Cloudflare Access 应用和策略。登录方式（邮箱 OTP、GitHub、Google 等）和允许的身份由你决定。Access 决定谁能打开页面；magpie 的 key 决定谁能读网关。
7. 构建并发布：

```sh
cd web
npm ci
npm run build
wrangler deploy
```

8. 自己验收（状态码以 Worker 源码为准，见第 4 节）：
   - 未通过 Access 时，`/proxy/*` 与 `/v1/collector/*` 返回 401，正文 `access_required`。
   - 已通过 Access 但没有 `X-Magpie-Gateway-Key` / `X-Magpie-Web-Key` 时返回 401，正文 `missing_key`。
   - 白名单以外的路径，以及 GET/HEAD 以外的方法，返回 404，正文 `not_found`。`OPTIONS` 返回 204。
   - 页面必须先过 Access 登录。

Worker 只代理下列 GET 和 HEAD。

网关侧，浏览器路径是 `/proxy/gateway` 加上：

- `/v1/magpie/usage`
- `/v1/magpie/usage/requests`
- `/v1/magpie/quotas`
- `/v1/magpie/quotas/cards`
- `/v1/magpie/quotas/history`
- `/v1/magpie/route`
- `/v1/magpie/concurrency`
- `/v1/magpie/limit`
- `/api/hello`

Web GUI 侧，浏览器路径是 `/proxy/web` 加上：

- `/api/gateway/trace`
- `/api/gateway/history`
- `/api/gateway/route`
- `/api/groups`
- `/api/providers`
- `/api/usage`
- `/api/usage/quotas`

`/api/usage/quotas` 上的 `asked` 查询参数会被删掉。配额请求不要自己加 `asked=1`，那会触发服务商用量读取。响应头 `X-Magpie-Reading: 1` 表示读取还在进行。

collector 侧允许 GET `/v1/collector/hello|sys|services|chart|tmux|tmux/capture|tasks|activity|repos|tailscale`，以及 `/v1/collector/runtimes` 和 `/v1/collector/runtimes/{id}`（id 为 `[a-z0-9_-]+`）。同一路径也可以从 `/proxy/collector` 前缀进来。不代理动作、`/v1/collector/snapshot`，也不代理 collector 上的 `/v1/collector/magpie/*`。

浏览器在 Live 模式把 gateway key、runtime key 放在当次请求的 `X-Magpie-Gateway-Key`、`X-Magpie-Web-Key`。Worker 改写成 `Authorization: Bearer <gateway-key>` 或 `Cookie: magpie_web_<WEB_PORT>=<web-key>`，并加上 `X-Forwarded-For` 与 `Forwarded`，然后丢掉原始 key 头、入站 `Cookie`（含 Access 的 `CF_Authorization`）和入站 `Authorization`。响应侧去掉 `Set-Cookie`。Worker 不记录、不缓存密钥。

设置页里的 Profile 存在 `localStorage` 键 `magpie.profiles`。导出的 JSON 不含密钥。密钥默认在 `sessionStorage`；勾选「记住 key（在此设备）」才写入 `localStorage`，是明文。Live 模式要看主机面板时，把 collector 地址填成这个 Worker 的源，例如 `https://<your-domain>`。页面会请求同源的 `/v1/collector/…`，由 Worker 附上 `COLLECTOR_KEY`。浏览器不保存 collector 动作密钥，直连请求也不会带 `X-Collector-Key`。collector 自己不开 CORS，所以不要让 HTTPS 页面直接去拉另一个源上的 `http://` collector。

直连模式只使用 gateway API：页面源要加入 magpie「Settings → Network and sharing → Web pages」，网关要用 HTTPS（`--tls-cert` 或 Tailscale Serve）。HTTPS 页面调用 `http://` 网关会被浏览器当成混合内容拦住。`http://` 直连只适合本机 `npm run dev` 或 `npm run preview`。直连没有全局 trace，Agent 只能按会话看 `/v1/magpie/route`。

域名用你自己的，例如 `https://<your-domain>`。文档示例写成 `https://magpie.example.com`。

### 1.4 iOS

系统要求 iOS 17+。Bundle ID 是 `io.github.logikinet.magpie-ios`，scheme 是 `magpie-ios`。

从 CI 拿未签名包：在 GitHub Actions 打开名为 CI 的工作流。`push` 到会改 `ios/**` 的提交，或手动 **Run workflow**（`workflow_dispatch`），会跑 `ios-build`。在该次运行的 Artifacts 里下载 `magpie-ios-ipa`。包内是未签名的 `magpie-ios.app`。签名和证书由你自己负责，可用轻松签（Esign）、LCSign，或 AltStore 类工具。

自己构建时，在 macOS 上：

```sh
cd ios
xcodegen generate
open magpie-ios.xcodeproj
```

在 Xcode 里选 scheme `magpie-ios` 和真机。要得到和 CI 一样的未签名 IPA，CI 用的命令是：

```sh
xcodebuild \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -project magpie-ios.xcodeproj \
  -scheme magpie-ios \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
mkdir Payload
cp -R build/Build/Products/Release-iphoneos/magpie-ios.app Payload/
zip -qry magpie-ios.ipa Payload
```

截图产物是另一份：`mock-screenshots`（iOS）和 `web-mock-screenshots`（Web）。它们不是安装包。

手机和跑 magpie 的机器都登录 Tailscale。主机名用 MagicDNS，例如 `devbox.example.ts.net`。在应用里为每台服务器新建 Profile：

- 网关 URL：优先 `https://<your-host>:3425`。端口通常是 `3425`，以网关设置为准。
- Web GUI URL：优先 HTTPS。runtime key 放在「Runtime 密钥」。
- Collector URL 和「Collector 密钥」：每个 Profile 各配一套。密钥进 iOS Keychain，账户名形如 `magpie-ios.<profile-uuid>.collectorKey`。请求头是 `X-Collector-Key`。
- SSH 主机、端口、用户，以及 ed25519 / RSA 私钥或密码。私钥、口令、密码、主机指纹也在 Keychain。

`http://` 可以使用，设置页和编辑页会显示「不安全（HTTP）」，并提示只在 Tailscale 这类私有网络里用。非本机访问要在 magpie 里开启 **Share on local network**。建议固定 `MAGPIE_WEB_KEY`。

若 collector 仍绑在 `127.0.0.1:8787`，手机经 Tailscale 访问不到它。要么让 collector 在带 `-allow-remote` 和读取密钥的前提下听 tailnet 地址，要么经 SSH / 你自己的 TLS 通道转到 `127.0.0.1:8787`。网关若设了 `MAGPIE_ADDR=127.0.0.1:<port>`，手机同样不能直接打开这个回环地址；直连手机时需要 Tailscale Serve 这类映射（见 `web/docs/architecture.md`），或者让网关听手机能够到达的地址。Web 走 Worker 时应保持回环，由 Tunnel / VPC 去连。

## 2. magpie 已知坑

这些行为来自本仓库对上游的记录，部署时按这个处理。

1. **403。** 非本机请求必须开启 **Share on local network**，并且带对 gateway key。否则网关返回 403 JSON。iOS 文案会提示开启该项并检查 gateway key。Web 文案是「访问被拒绝，请开启局域网共享并检查 gateway key。」
2. **Web trace 的 cookie。** `/api/*` 不认 gateway key。用 `?k=<web-key>` 打开 Web GUI 一次，服务器写下 `magpie_web_<port>`（HttpOnly、SameSite=Lax、Path=/）。之后的请求要带这个 cookie。iOS 可以把 key 放在 Keychain，直接发送 `Cookie: magpie_web_<port>=<web-key>`。端口必须是 Web GUI 的端口，和 Worker 的 `WEB_PORT` 一致。Web 设置页里的「Web GUI 端口」会写入 Profile 的 `webPort`，当前请求不用它来拼 cookie。
3. **固定 `MAGPIE_WEB_KEY`。** 不固定的话，magpie 每次重启都会换 runtime key，trace 变成 401/403。应用会提示重新从 Web GUI 复制 key。
4. **不要设置 `MAGPIE_TRUST_PROXY`。** Worker 靠转发头让打到 `127.0.0.1` 的请求按远程请求处理，从而强制校验 gateway key。设了 `MAGPIE_TRUST_PROXY` 或 `MAGPIE_TRUST_PROXY=1` 会拆掉这层检查。

另外：trace 第一次用 `GET /api/gateway/trace?after=0`，不要带 `wait`。之后带 `wait=1`，服务端最多保持约 25 秒。客户端超时是 35 秒。`mine=false` 表示离线，约 5 秒后重试；其他错误约 3 秒后重试。返回的 `seq` 变小就要清空已积累的路由。当前请求取 `seq` 最大的那条，不要假定 `routes[0]` 是最新的。直连模式没有这条全局 trace。

## 3. 可选：oh-my-free-models

本仓库没有集成这个代理，也没有它的配置文件。下面只说明一种常见接法，密钥不要写进本仓库或 App。

可以在跑 magpie 的同一台机器上安装 [oh-my-free-models](https://github.com/hakilee/oh-my-free-models)：

```sh
npm i -g oh-my-free-models
```

它默认听 `http://localhost:4567`，只应绑在本机或私有网络。在 magpie 里把它配成某个路由组的第一个自定义 provider，DeepSeek 官方 API 作为 fallback。Claude Code 走该代理的 `/anthropic` 路径。你自己的 OpenRouter、NVIDIA 密钥放在 `~/.oh-my-free-models/.env`，不要使用来路不明的公共中转。

App 和 Web 没有内置 provider 列表。配额、路由、并发都显示网关返回的内容，所以在 magpie 里增删 provider 不用改客户端。

## 4. 排障手册

先看界面上的原文，再对下面的表。iOS 网络错误来自 `MagpieError` 的中文说明，设置等操作失败时走应用内的 `ErrorMessages`。Web 错误在页面上，细节在浏览器控制台。不要把 key、cookie 贴到 Issue 里。

| 症状 | 检查 | 修复 |
| --- | --- | --- |
| App 连不上 | 网关 URL 是否含协议和端口；手机与 `<your-host>` 是否都在 Tailscale 上；collector 是否仍只听 `127.0.0.1` | 用 MagicDNS 全名。网关端口通常 `3425`。collector 要让手机可达时，加上 `-allow-remote` 和读取密钥，或经 SSH/TLS 转到回环。看 iOS 里的「网络连接失败，请检查网络和服务器地址。」 |
| 路由图是空的，或不是实时的 | Live 还是直连；`GET /api/gateway/trace?after=0` 是否 200；`mine` 是否为 false；`WEB_PORT` 是否等于 Web GUI 端口 | 全局 trace 只在 Live / 带 runtime key 的 `/api/gateway/trace` 上。直连只有单会话 `/v1/magpie/route`。`mine=false` 时界面是离线，5 秒后重试。页面进后台会停轮询。用 `seq` 最大的路由当当前请求 |
| 长轮询报错或很快超时 | 客户端超时是否盖过服务端最长约 25 秒的等待；Worker 到上游的时限是 40 秒 | 保持客户端 35 秒超时。401/403 会停轮询并要求重新认证，不会自动重放业务请求。Worker 超时返回 504 `upstream_timeout`，连不上返回 502 `upstream_unreachable` |
| 配额卡片是空的 | `/v1/magpie/quotas/cards` 与 `/api/usage/quotas` 的正文；响应是否带 `X-Magpie-Reading: 1`；gateway key 是不是 held key | 不要加 `asked=1`。`X-Magpie-Reading: 1` 时稍后再请求。held key 不能看用量汇总。collector 没有可读的本地额度文件时会省略额度，不会填 0 |
| collector 401 / 403 | `hello` 是否要求读取密钥；写操作是否同时开了开关和动作密钥；请求是否来自浏览器 | GET 用 `<collector-read-key>`。401 正文是 `read token required` 或 `action token required`。403 正文是 `actions disabled`（写未开启）或拒绝了带 `Origin` 的请求。读取密钥不能当动作密钥 |
| Worker 拦截了路径 | 路径是否在第 1.3 节的白名单；方法是不是 GET/HEAD；查询串是否长于 2048 | 不在名单里返回 404 `not_found`，包括 POST、`/v1/collector/actions/*`、`snapshot`、collector 的 `magpie/*`。查询过长返回 400 `query_too_long`。未配置 `COLLECTOR_URL` 或 `COLLECTOR_KEY` 时 collector 代理返回 503 `collector_unconfigured` |
| Access 来回跳转 | `ACCESS_TEAM_DOMAIN`、`ACCESS_AUD` 是否就是这个域名上的 Access 应用；浏览器是否带 `Cf-Access-Jwt-Assertion` 或 `CF_Authorization` | 团队域或 AUD 不一致时，Worker 对 `/proxy/*` 和 `/v1/collector/*` 返回 401 `access_required`，Access 又把用户送去登录，看起来像循环。改完 `vars` 后重新 `wrangler deploy`。不要在公网域名上依赖 `ACCESS_DISABLED` |
| Tailscale 不通 | 两边是否登录；Profile 里的主机名能否从手机解析；目标是否只听 `127.0.0.1` | `127.0.0.1` 不会出现在 tailnet 上。手机直连要用 MagicDNS 名加手机能够到达的端口，或使用文档里的 Tailscale Serve 映射。collector 默认地址手机访问不到 |
| 按天分组差了一天 | 手机或浏览器时区，对照提交时间戳 `ts`（Unix 秒） | Web 用运行环境的本地日历日（`YYYY-MM-DD`）。iOS 用 `Calendar.current` 的当天，标题带本地时区的日期。设备时区和主机不一致时，「今天」跟设备走。`/api/gateway/history?day=YYYY-MM-DD` 的 `day` 是调用方传入的日历日 |
| 界面写着不安全 | URL 是否以 `http://` 开头 | 这是预期提示，不是连接失败。改成 `https://` 后徽章消失。私有网络上可以继续用 HTTP，流量不加密 |

### curl

在 collector 所在机器上：

```sh
curl -sS -D - -H "X-Collector-Key: <collector-read-key>" \
  http://127.0.0.1:8787/v1/collector/hello
curl -sS -H "X-Collector-Key: <collector-read-key>" \
  http://127.0.0.1:8787/v1/collector/sys
curl -sS -H "X-Collector-Key: <collector-read-key>" \
  "http://127.0.0.1:8787/v1/collector/services?scope=all"
```

在 magpie 所在机器上。Web GUI 端口换成实际端口：

```sh
curl -sS -H "Cookie: magpie_web_<web-port>=<web-key>" \
  "http://127.0.0.1:<web-port>/api/gateway/trace?after=0"
curl -sS -H "Cookie: magpie_web_<web-port>=<web-key>" \
  "http://127.0.0.1:<web-port>/api/groups"
```

网关（默认 `127.0.0.1:3425`）。`Authorization: Bearer` 与 `x-api-key` 都可以：

```sh
curl -sS -H "Authorization: Bearer <gateway-key>" \
  http://127.0.0.1:3425/v1/magpie/limit
curl -sS -H "x-api-key: <gateway-key>" \
  http://127.0.0.1:3425/v1/magpie/quotas
curl -sS -H "Authorization: Bearer <gateway-key>" \
  "http://127.0.0.1:3425/v1/magpie/quotas/cards"
curl -sS -H "Authorization: Bearer <gateway-key>" \
  "http://127.0.0.1:3425/v1/magpie/usage?period=today"
```

经过已经部署的 Worker 时，用你的域名。没带 Access 身份时应得到 401：

```sh
curl -sS -D - "https://<your-domain>/v1/collector/hello"
curl -sS -D - -H "X-Magpie-Gateway-Key: <gateway-key>" \
  "https://<your-domain>/proxy/gateway/v1/magpie/limit"
curl -sS -D - -H "X-Magpie-Web-Key: <web-key>" \
  "https://<your-domain>/proxy/web/api/gateway/trace?after=0"
curl -sS -D - -X POST "https://<your-domain>/proxy/gateway/v1/magpie/quotas"
```

最后一条应是 404。`web/README.md` 的验收清单写的是「无 key 返回 403、POST 返回 404/405」。当前 Worker 在缺 key 时返回 401 `missing_key`，未过 Access 时返回 401 `access_required`，不允许的方法返回 404 `not_found`。请求已经到达 magpie、但未开共享或 gateway key 不对时，才是 magpie 自己的 403。

### 日志放哪里

| 位置 | 怎么看 |
| --- | --- |
| collector 用户单元 | `journalctl --user -u magpie-collector.service`。单元名与 `collector/deploy/magpie-collector.service` 的文件名一致。进程会打出监听地址，以及 `readonly=true/false` |
| 审计日志 | 默认 `$HOME/.local/state/magpie-collector/collector-audit.jsonl`，模式 `0600`。只在发生写请求时追加 |
| Worker | `wrangler tail`。Worker 故意不把密钥、任意路径和查询串打到日志里，tail 里看不到 key 是预期行为 |
| 浏览器 | 开发者工具的控制台与网络面板。看状态码和页面上的中文错误，不要复制请求头里的 key |
| iOS | 页面上的中文错误。认证失败会提到 gateway key、`MAGPIE_WEB_KEY` 或 **Share on local network**。SSH 指纹变化要在设置里清除该 Profile 的指纹后再连 |

## 5. 部署之后

### 还没做完的部分

这些是当前代码的缺口，不是配置步骤。

- **写操作按钮没有接到界面。** collector 的 POST `/v1/collector/actions/...` 已经实现，但 Web 在 `readonly=false` 时只显示禁用按钮，文案是「操作尚未接入」。Worker 也不转发这些路径。iOS 服务页的启动 / 停止走 SSH 上的 `systemctl` / `docker`，不调用 collector 的动作接口。
- **iOS 没有「刷新额度」按钮去打 `quota-refresh`。** 用量页的「刷新」会重新 GET 用量。运行时页出现时 GET `/v1/collector/runtimes`。服务端的 `quota-refresh` 只会让下一次读取重新取额度，界面没有调用它。
- **iOS 没有手动主题开关。** 外观跟随系统。`forceDark` 只是截图任务写进 UserDefaults 的开关，设置页里没有。Web 设置里已经可以选「跟随系统 / 浅色 / 深色」，存在 `localStorage` 键 `magpie.theme`，也可以用 `?theme=light` 或 `?theme=dark`。
- **公开页不会默认模糊。** 模糊只在用户打开「隐藏账号」之后加上（样式 `filter: blur(2.2px)`）。Mock 演示和未开此开关的页面不会自动模糊账号。
- **iOS 的「网页」服务筛选使用固定端口。** `80`、`443`、`3000`、`3426`、`5173`、`8000`、`8080`、`8787`。它不看 collector 返回的 `web` 字段。collector 自己是对 `127.0.0.1:<port>/` 做 HTTP HEAD，失败再 GET，从而设置 `web`。Web 界面认 `web`、`http`、`scheme` 或 `url`。

### 安全加固

- collector 保持 `127.0.0.1:8787`。只有在读取密钥已经设置时才加 `-allow-remote`。
- 读取密钥和动作密钥分开。默认不要开 `MAGPIE_COLLECTOR_ALLOW_ACTIONS`。
- `units` 只写你确实要启停的 `user:<name>.service` 或 `system:<name>.service`。
- 配置、环境文件、审计日志保持 `0600`。单元已设 `UMask=0077`。
- 不要开 `MAGPIE_COLLECTOR_EXPOSE_CMDLINE`，除非你需要看脱敏后的命令行。
- 网关给 Worker 用时绑定 `MAGPIE_ADDR=127.0.0.1:<port>`，并保持 **Share on local network** 开着，这样转发头会让请求按远程校验。
- 不要设置 `MAGPIE_TRUST_PROXY`。
- `COLLECTOR_KEY`、gateway key、runtime key 不进 `wrangler.jsonc` 的 `vars`，不进 Git，不进 Profile 导出文件。
- Web 密钥尽量留在 `sessionStorage`。HTTP 只在 Tailscale 等私有网络使用。
- Worker 白名单保持只读。不要为了省事去代理整个 `/api/*` 或动作接口。runtime key 在 magpie Web GUI 上能改设置。

### 备份

| 内容 | 位置 |
| --- | --- |
| iOS 服务器列表 | 应用的 Application Support 目录里的 `profiles.json`。里面没有密钥 |
| iOS 密钥与 SSH 指纹 | Keychain。账户名 `magpie-ios.<profile-uuid>.collectorKey`、`gatewayKey`、`runtimeKey`、`sshPrivateKey`、`sshPassphrase`、`sshPassword`、`hostKey`。卸载应用会丢掉钥匙串项，导出 Profile 也不会带上它们 |
| collector 配置 | `$HOME/.config/magpie-collector/config.json` 与 `environment` |
| 审计日志 | 默认 `$HOME/.local/state/magpie-collector/collector-audit.jsonl` |
| Web Profile | 浏览器 `localStorage` 的 `magpie.profiles`。设置页可以导出 JSON，文件不含密钥 |
| Web 密钥 | 默认 `sessionStorage`。只有勾了「记住 key」才在 `localStorage`。换浏览器或清站点数据后要重填 |

### 更新

```sh
git pull
```

- collector：在 `collector/` 再执行 `go build -o magpie-collector ./cmd/magpie-collector`，装回 `$HOME/.local/bin/magpie-collector`，然后 `systemctl --user restart magpie-collector.service`。
- web：在 `web/` 执行 `npm ci` 和 `npm run build`，再 `wrangler deploy`。改了 `wrangler.jsonc` 的 `vars` 也要重新部署。secret 没变就不用重设。
- iOS：重新下载 CI 产物 `magpie-ios-ipa` 并重新签名安装，或在本地按第 1.4 节再构建。Profile 和 Keychain 留在设备上，不在 IPA 里。

CI 不会发布 collector 二进制，也不会替你执行 `wrangler deploy`。

### 反馈

到 GitHub 仓库 [Logikinet/magpie-monitor](https://github.com/Logikinet/magpie-monitor) 的 Issues 提交。写上：哪一端（iOS / Web / collector）、Profile 是 Live、直连还是 Mock、HTTP 状态码、界面上的中文错误原文。不要附带 gateway key、runtime key、collector 密钥、cookie、SSH 私钥或 `environment` 文件。
