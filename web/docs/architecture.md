# magpie-web 架构设计

> 面向 yetone/magpie LLM 网关的 Web 远程监控面板，是已完成的 Logikinet/magpie-monitor 的网页版伴侣。
> 本文为设计文档，不含实现代码。所有 API 事实以 `docs/magpie-api-notes.md` 为准（已对照 yetone/magpie 源码 @ e085d6e，2026-10-17 核对）。
> 仓库后续可能公开：全文不出现真实主机名、IP、密钥、个人信息或私有链接，示例一律使用 `magpie.example.com` 等占位符。

## 1. 目标与非目标

### 目标（Goals）
- 在桌面与移动浏览器上远程查看 magpie 网关的运行状态、配额、请求流水与实时路由。
- 复用 iOS 已建立的视觉语言与信息结构（概览 / 动态 / Agent / quotas/stats），提供一致的中文界面。
- 以「安全优先」的方式托管：网关不直接暴露公网，gateway key 不出现在公开内容中，登录走 Cloudflare Access。
- 支持多服务器 Profile 切换，便于同时监控多台 magpie 实例。
- 提供三种连接模式：经代理的 Live、网关直连（gateway-only 降级）、Mock 数据模式（零后端，可用于公开演示与截图）。
- 纯 TypeScript 可测核心（解码、请求构造、长轮询状态机、代理头逻辑），可在 Linux 上以 Vitest 验证。
- Playwright 在 Mock 模式下产出桌面/移动、浅色/深色截图，作为 UI 验收与公开演示素材。

### 非目标（Non-goals）
- **不** 部署、启动或配置 magpie 本身（只读监控，不写 magpie 配置或数据库）。
- **不** 在纯浏览器中实现 iOS 的 Tmux / 服务（SSH docker/systemd）能力——浏览器无法直接 SSH，首版仅降级为链接跳转或可选中继，见 §2。
- **不** 在服务端持久化存储任何密钥；Worker 只做逐请求透传。
- **不** 注入路由规则、不做全量 agent 会话控制（只读 trace）。
- **不** 做后台无限轮询（页面隐藏即暂停，见 §9）。
- **不** 自创样式；只使用设计 token 中真实存在的间距、圆角、语义色与状态，见 §11。

## 2. 功能映射

### iOS 五个 Tab → Web
| iOS Tab | Web 落地 | 说明 |
| --- | --- | --- |
| 概览 | 概览页 | 端口/容器/systemd/进程等主机信息在纯浏览器中**不可直采**，改为展示网关侧可得的连接/异常与配额摘要（`/api/hello`、`/v1/magpie/limit`、配额卡片、并发概览）。 |
| 动态 | 动态页 | `/v1/magpie/usage/requests?period=&offset=&limit=&<filters>` 的 Ledger 分页 + 顶部 `bucket/series` 趋势（数据驱动，不硬编码）。 |
| Agent | Agent 页 | 实时 trace 长轮询 `/api/gateway/trace?after=<seq>&wait=1`；gateway-only 降级为 `/v1/magpie/route?session=<id>&after=<seq>&wait=<secs>` 单会话轮询。 |
| quotas/stats | 配额页 | `/v1/magpie/quotas`、`/quotas/cards`、`/quotas/history`、`/v1/magpie/concurrency`。 |
| 服务 / Tmux | 链接跳转或可选中继 | 浏览器无 SSH/PTY 能力，见下。 |

### Tmux / 服务 可选方案
| 方案 | 做法 | 代价 | 是否推荐 |
| --- | --- | --- | --- |
| 省略 | 不提供；提示用户继续使用 iOS 的 SSH/PTY 能力。 | 无 | **首版推荐** |
| 链接跳转 | 在 Profile 里配置一个可选的 magpie Web GUI 地址，按钮直接新窗口打开（由用户自行负责鉴权与网络可达）。 | 极低，仅一个外链 | 可与「省略」并存 |
| 可选中继/agent | 在 magpie 主机上跑一个小型可选 agent（例如基于 WebSocket 的 SSH 桥接，或复用 ttyd），置于 Cloudflare Access 之后，Web 端以受限终端形态接入。 | 高：新增常驻进程、SSH 凭据与安全面 | 二期再评估，**不在首版范围** |

结论：首版采用「省略 + 可选链接跳转」，把 SSH/PTY 留给 iOS。中继/agent 仅作为后续可选增强记录，不进入当前任务分解。

## 3. 托管方案对比

用户目标部署在 Cloudflare（Pages/Workers）。三种候选：

| 维度 | (a) 静态 SPA → magpie 直连（Tailscale HTTPS + CORS 白名单） | (b) Cloudflare Worker 代理 + Cloudflare Tunnel + Cloudflare Access | (c) 自托管静态文件与 magpie 同源（Tailscale Serve 路径映射 / Caddy） |
| --- | --- | --- | --- |
| 安全 | 网关经 Tailscale HTTPS 可达，但每个可访问者需自行过 magpie 的 CORS 与 key 校验；网关依赖 Tailscale 作为唯一边界。 | **网关零公网暴露**；仅 Worker 经私有 Tunnel 触达 127.0.0.1；Access 在入口做身份认证。 | 依赖自托管反向代理做边界；Tailscale 之外无额外身份层。 |
| CORS | 必须在 magpie 设置「Web pages」里把 SPA 源加入白名单，否则 403；`/api/*` 本身无 CORS，无法跨源调用。 | 同源（SPA 与 `/api` 同属一个 Worker 源），**不触发浏览器 CORS**。 | 同源，无 CORS 问题。 |
| Cookie / trace 可行性 | `/api/*` 无 CORS 且 `SameSite=Lax` cookie 跨站不携带，浏览器又禁止 JS 写 `Cookie` 头 → trace 基本不可用。 | Worker 服务端把逐请求 runtime key 转成 `Cookie: magpie_web_<port>=<key>`，trace 可用。 | 同源反向代理可转发 cookie，可用，但需自维护代理配置。 |
| 搭建成本 | 低（纯静态 + Tailscale 已有）。 | 中（Worker + Tunnel + Access 一次性配置）。 | 中（自建代理 + 证书 + 维护）。 |
| 分享给他人 | 依赖 Tailscale 组网，分享门槛高。 | 自定义域名 + Access 登录，可精细到邮箱/身份源。 | 依赖自托管入口，分享与安全都靠用户自维护。 |
| Cloudflare 契合度 | 仅作静态托管，不解决安全边界。 | **原生契合**：Workers VPC + Tunnel + Static Assets + Access 全链路都在 Cloudflare。 | 低，Cloudflare 只当 CDN。 |

**推荐：(b) Cloudflare Worker 代理 + Cloudflare Tunnel（无公网主机名）+ Cloudflare Access。**
理由：安全第一。网关始终只监听 127.0.0.1，永不暴露公网；gateway key 只在浏览器→Worker 的当次请求中出现并由 Worker 逐请求转换后丢弃，绝不落盘、绝不写日志；所有访问先过 Access 登录。同时 SPA 与代理同源，绕开 `/api/*` 无 CORS 与跨站 cookie 的限制，Agent trace 长轮询可用。(a) 在 `/api/*` 上不可行，(c) 缺乏身份层且把安全边界压给用户自维护。

### 请求流（ASCII）
```
浏览器 (SPA)                Cloudflare Worker             Cloudflare Tunnel            magpie (127.0.0.1)
│ https://magpie.example.com          │                (cloudflared, QUIC/UDP 7844)      GATEWAY / WEB GUI
│  1) Access 登录后请求页面             │                              │                        │
│ ──────────────────────────────►     │                              │                        │
│  2) 静态资源 (Workers Static Assets)  │                              │                        │
│ ◄──────────────────────────────     │                              │                        │
│  3) /api/* 或 /v1/magpie/*           │                              │                        │
│     携带 X-Magpie-Gateway-Key /      │
│     X-Magpie-Web-Key（仅本次请求）     │                              │                        │
│ ──────────────────────────────►     │  4) 注入转发头                 │                        │
│                                     │     (如 Cf-Connecting-IP)      │                        │
│                                     │ ────────────────────────────► │  5) 命中 127.0.0.1       │
│                                     │                              │     且带转发头 => REMOTE │
│                                     │                              │     强制校验 gateway key │
│                                     │  6) 转换凭据：                 │                        │
│                                     │     /api/* → Cookie:          │                        │
│                                     │       magpie_web_<port>=<key> │                        │
│                                     │     /v1/magpie/* →            │                        │
│                                     │       Authorization: Bearer   │                        │
│                                     │ ────────────────────────────► │                        │
│                                     │  7) 响应回传                   │                        │
│ ◄──────────────────────────────     │ ◄──────────────────────────── │                        │
│  8) Worker 不记录、不存储、不缓存任何 key │                              │                        │
```

### 头部处理（关键，安全相关）
- gateway key 与 runtime key 是两把不同的 key：浏览器分别放在**当次请求**的自定义头 `X-Magpie-Gateway-Key`（→ `/v1/magpie/*`）与 `X-Magpie-Web-Key`（→ `/api/*`）里，不写入 URL、不留 Cookie。
- Worker 收到后按目标路由转换（并删除这两个自定义头，不向上游转发原值）：
  - `/api/*` → 写 `Cookie: magpie_web_<port>=<key>`（cookie 名含端口，Profile 的 web 端口必须与之一致）。
  - `/v1/magpie/*` → 写 `Authorization: Bearer <gateway key>`。
- Worker **同时注入转发头**（如 `Cf-Connecting-IP` 或 `X-Forwarded-For`）。magpie 的代理检测规定：命中 127.0.0.1 且带转发头时按 REMOTE 处理，gateway key 才会被强制校验；不带转发头会被当作 local（任意 token 都通过）。
- **绝不设置 `MAGPIE_TRUST_PROXY=1`**：这会禁用上述转发头检测，导致 key 校验失效。
- **绝不** 在 Worker 端记录、写日志、缓存或存储任何 key（包括运行时 key 与 gateway key）。无 key 的静态资源请求不注入任何凭据。
- **路径白名单**：Worker 只代理本面板需要的只读路由（`GET /v1/magpie/{usage,usage/requests,quotas,quotas/cards,quotas/history,route,concurrency,limit}`、`GET /api/hello`、`GET /api/gateway/{trace,history}`），其余一律 404。runtime key 能操作 magpie web 的设置与密钥，绝不能把整个 `/api/*`（含 POST）透传出去。
- **清理入站头**：转发前删除浏览器带来的 `Cookie`（含 Access 的 `CF_Authorization`）、`Authorization` 及任何既有转发头，再按上面规则重建；响应侧删除上游 `Set-Cookie`。
- **Access 纵深防御**：Worker 校验 `Cf-Access-Jwt-Assertion`（团队域 + AUD），校验失败直接 401，防止 Access 配置失误时代理裸奔。
- 转发头经 Workers VPC / cloudflared 后是否原样到达 magpie **待验证**：T6 必须用「不带 key 的请求应得 403」做实测验收。
- 关键字段名（自定义头名、转发头选择）在实现前与用户确认，见 §18。

## 4. 认证与密钥存储

### 网关认证（Bearer）
- 所有 `/v1/magpie/*` 请求由 Worker 注入 `Authorization: Bearer <gateway key>`（等价 `x-api-key`）。
- 非本机访问需 magpie 开启「Share on local network」且带 key，否则 403 JSON 错误。经 (b) 方案时，转发头使请求恒为 REMOTE，校验始终生效。
- 开启共享时 magpie 默认改为监听 `0.0.0.0`；在 magpie 主机设置 `MAGPIE_ADDR=127.0.0.1:<port>` 可保持共享（要求 key）但监听仍只在回环（源码 lan.go 注释的「behind Tailscale Serve」用法），这样网关不会因此暴露到局域网/tailnet。

### Web GUI 认证（Cookie）
- `/api/*` 由 runtime key 保护。magpie 源码里打开 `?k=<KEY>` 链接下发 cookie `magpie_web_<port>`（HttpOnly、SameSite=Lax、Path=/；固定 `MAGPIE_WEB_KEY` 时 MaxAge 400d，否则 session）。
- 浏览器无法跨站携带该 `SameSite=Lax` cookie，也无法用 JS 设置 `Cookie` 头；因此由 Worker 在服务端把 `X-Magpie-Web-Key` 转成 `Cookie` 头（见 §3）。
- key 轮换：magpie 重启后 runtime key 变化 → `/api/*` 返回 401/403 → 前端提示「建议在 magpie 设置固定 `MAGPIE_WEB_KEY`」，并请求用户重新复制 key。

### 浏览器存储策略（明确策略，不静默）
- 默认 `sessionStorage`（关闭标签即清，key 不跨会话留存）。
- 用户勾选「记住 key」后才写入 `localStorage`；入口处给出**明确警告 UI**，说明 key 以明文存于本浏览器、任何能访问该浏览器配置文件的人都可读取。
- 提供一键「清除已存 key」按钮；Profile 列表/设置页显示当前 key 是否被记住。
- key 只用于发起请求，绝不写入日志、错误上报、URL、`referrer` 或截图（Mock 模式无真实密钥）。

### Cloudflare Access
- Worker 的自定义域名置于 Cloudflare Access（Zero Trust）之后，登录身份源可选邮箱 OTP / GitHub / Google；允许的邮箱/身份由用户决策（§18）。
- Access 负责「谁能打开页面」，magpie 的 key 负责「谁能读写网关」，两层不混用。

## 5. 连接模式

| 模式 | 说明 | 适用 |
| --- | --- | --- |
| Live（经代理） | 走 §3 的 Worker 代理，`/api/*` 与 `/v1/magpie/*` 全功能。 | 生产/日常监控，**默认**。 |
| 直连（gateway-only 降级） | 浏览器直接调用 `/v1/magpie/*`（`Authorization: Bearer`）。前提：页面源已列入 magpie「Web pages」CORS 白名单，且网关为 HTTPS（`--tls-cert` 或 Tailscale Serve）——HTTPS 页面调用 `http://` 网关会被浏览器按混合内容拦截，`http://` 只在本地 `npm run dev`/`vite preview` 时可用。Agent 页退化为单会话 `/v1/magpie/route?session=<id>&after=<seq>&wait=<secs>` 长轮询，没有全局 trace 流；Web GUI 专属的 `/api/gateway/*` 不可用。 | 用户只给 gateway 端点/key，无 Web GUI 或无法部署 Worker 时。 |
| Mock | 所有 client 走 `MockTransport`，读本地 Fixture JSON，不触网；全程显示「模拟数据」徽章。 | 演示、截图、公开 demo、无后端开发。 |

- 每个 Profile 标注其模式；直连模式在 Agent 页显示「gateway-only（无全局 trace）」提示。
- **分享给他人**：Live 模式的 Worker 通过 VPC 绑定只能到达部署者自己的 magpie，所以别人用的方式有三种：自己 fork 后 `wrangler deploy`（README 给出步骤，所有 ID 都写在 `wrangler.jsonc` 变量里，不硬编码），使用直连模式，或只打开公开的 Mock 演示站。Profile（服务器地址、模式）可以导出/导入为 JSON，导出时**不含** key。
- Mock 模式为零后端要求，可作为公开演示站直接部署。

## 6. 技术栈（小而简单，给出理由）

- **Vite + TypeScript**：静态构建快、类型贯穿核心解码/请求层，便于在 Linux 上跑 Vitest。
- **轻量框架：Preact（或 Svelte/Lit，待用户决策）**：本项目以列表、卡片、状态与轮询为主，不需要重型框架；轻框架 bundle 小、心智负担低，契合「小而一致」的原则。首版建议 Preact。
- **不引入** 状态机库、重型 UI 库或图表库：长轮询状态机用纯函数实现以便测试；趋势图用少量 SVG/CSS 绘制，遵循「数据驱动、不硬编码、不装饰」。
- **Vitest**（单元 + fake timers）+ **Playwright**（Mock 模式截图）。两者均可在 Linux 运行。
- CSS：自定义属性承载设计 token，`prefers-color-scheme` 做深浅色，`prefers-reduced-motion` 做动效降级，见 §11。

## 7. 目录结构

```
magpie-web/
  docs/
    architecture.md
  src/
    main.ts
    app.tsx
    styles/
      tokens.css            # 设计 token（CSS custom properties）
    core/
      decode.ts             # 容错解码（§8）
      transport.ts          # Transport 抽象 + Live/Mock（§9）
      gateway-client.ts     # /v1/magpie/*（§9）
      web-client.ts         # /api/*（§9）
      proxy.ts              # 纯函数：X-Magpie-Gateway-Key → Bearer、X-Magpie-Web-Key → Cookie + 转发头
      longpoll.ts           # 长轮询状态机（§9）
    state/
      store.ts              # 全局状态
      profiles.ts           # Profile 列表/持久化
      keys.ts               # key 读取/写入/清除（§4）
    ui/
      status.tsx            # 状态图标 + 中文标签（§11）
      metric-card.tsx
      badge.tsx             # 不安全/模拟数据徽章
    views/
      overview.tsx
      activity.tsx
      agent.tsx
      quotas.tsx
      services.tsx          # 链接跳转（§2）
      settings.tsx
    mock/
      fixtures/*.json       # 脱敏 Fixture（Ledger/Quota/Trace/Concurrency/…）
  tests/
    unit/*.test.ts          # Vitest：decode/request/longpoll/proxy
    e2e/*.spec.ts           # Playwright 截图
  package.json
  vite.config.ts
  vitest.config.ts
  playwright.config.ts
```

核心逻辑（`core/`）不依赖框架，可在纯 Node/Vitest 环境测试；`ui/` 与 `views/` 只消费核心层，Mock 与 Live 对 UI 无感知。

## 8. 数据模型与容错解码

所有模型在 TypeScript 中以宽松类型描述，解码采用容错策略（与 iOS 对齐）：
- **未知字段**：忽略。
- **可选字段**：API 中大量 `?` 字段（`session_role?`、`priced`、`swapped`、`routed?`、`source?` 等）一律 `T | null | undefined`。
- **类型漂移**：`cost`/`total`/`seq` 等可能是 number 或数字字符串，统一经 `toNumber()` 包装，避免服务端改字符串导致整屏解码失败。
- **日期**：时间字段格式不唯一，`parseTime()` 依次尝试 ISO8601 及常见变体（`yyyy-MM-dd'T'HH:mm:ssXXX`、带毫秒），失败则回退 `rawTime: string` 供原样展示。
- **行级容错**：`rows[]`、`data[]`、`routes[]` 单条解码失败只跳过并计数坏行，不拖垮整屏。

### 关键模型（字段以 `magpie-api-notes.md` 为准）
```
GatewayHello   { name, version }
Ledger         { callerKeys:[Group], period, rows:[Row], offset, total, bucket, series:[SeriesPoint] }
Row            = Record + { session_role?, cost:number, priced:boolean, swapped?, routed?, source?,
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
TraceEnvelope  { seq, routes:[Route], totals:{requests,rerouted,errors}, mine:boolean, now }
Route          { seq,id,time,agent,parentSession?,session?,usage?[],kind?,model,effort?,tier?,
                 provider,group?,rule?,leadAccount?,subagent?,pinned?,order:[Weighed],…,priced }
```

- 5 小时与周配额：`Quota.windows` 中按 `name` 找到 5-hour / weekly 两个 `QuotaSpan`（各有 `used/remaining/resetsAt`）。
- `/v1/magpie/usage/requests` 返回 `offset/total`，分页以二者为边界。

## 9. 网络层与长轮询

### 传输抽象
`Transport` 接口：`request(path, init) -> Promise<{status, headers, body}>`
- `LiveTransport`：`fetch` 实现，默认不自动携带跨站凭据（凭据由 Worker 注入）。
- `MockTransport`：读 Fixture JSON，按路径 + query 返回假数据，可注入延迟/错误。
- 所有 client 依赖该接口，测试/截图替换实现。

### GatewayClient
- `GET /v1/magpie/usage?period=`、`/usage/requests?period=&offset=&limit=&filters`、`/quotas`、`/quotas/cards`、`/quotas/history?days=&provider=&user=`、`/route?session=`、`/concurrency`、`/limit`。
- Live 模式带 `X-Magpie-Gateway-Key`（Worker 转为 `Authorization: Bearer`，见 §3）；直连模式直接带 `Authorization: Bearer`。
- 普通请求超时 15s；长轮询见下。

### WebClient（经代理）
- `GET /api/gateway/trace?after=<seq>`（首个请求不带 `wait`）、`/api/gateway/history?day=YYYY-MM-DD`、`/api/gateway/route?id=<id>&day=<day>`、`/api/groups`、`/api/providers`、`/api/usage?period=<period>`、`/api/usage/quotas`。
- 带 `X-Magpie-Web-Key`（Worker 转为 `Cookie: magpie_web_<port>=<key>`）；只在 Live 模式可用。
- 401/403 → 触发 §4 的 key 重取提示，不自动重试业务请求。
- 配额请求默认不带 `asked=1`，因为它会触发服务商用量读取；响应头 `X-Magpie-Reading: 1` 表示读取仍在进行，稍后再请求。

### Worker 路由白名单

Worker 仅转发显式列出的路径和方法：gateway 侧 GET/HEAD 为 `/v1/magpie/usage`, `/usage/requests`, `/quotas`, `/quotas/cards`, `/quotas/history`, `/route`, `/concurrency`, `/limit`；Web GUI 侧 GET/HEAD 为 `/api/hello`, `/api/gateway/trace`, `/api/gateway/history`, `/api/gateway/route`, `/api/groups`, `/api/providers`, `/api/usage`, `/api/usage/quotas`。配额代理会删除 `asked` 查询参数。未知路径和写方法返回 404。

Collector 代理仅允许 GET `/v1/collector/{hello,sys,services,chart,tmux,tmux/capture,tasks,activity,repos,tailscale}` 与 `/v1/collector/runtimes`、注册运行时详情 `/v1/collector/runtimes/{id}`；不代理动作、snapshot 或 collector 的 magpie 聚合端点。认证、参数和接口契约见 [Collector API](../../docs/collector-api.md)。

### 长轮询循环（trace）
状态机（纯函数，Linux 上可用 fake timers 测试）：
```
init(after: 0)
loop:
  request trace?after=lastSeq + (loaded ? "&wait=1" : "")  // 首个无 wait，后续最多 hold 25s
  on success(env): if env.seq < lastSeq clear routes; lastSeq = env.seq; keep newest 60; yield routes
  on mine=false: show offline; wait 5s; loop
  on error: wait 3s; loop
  on cancelled: exit
```
- **超时**：客户端请求超时设 **35s**（> 服务端 25s），避免误判超时。
- **取消**：`AbortController` 绑定当前轮询；`visibilitychange` 隐藏、路由切换（切页）时 `abort()` 并释放连接。
- **暂停**：页面隐藏 → 停止所有长轮询与短轮询；重新可见 → 重建循环。
- **短轮询**：概览/动态/配额采用前台 20s 短轮询（可配置），后台一律停止。
- **重试**：`mine=false` 显示离线并在 5s 后重试；请求错误在 3s 后重试。401/403 同时提示重新认证。

### 动态 Tab 分页
`/usage/requests?offset=&limit=` 返回 `offset/total`；列表滚动到底加载下一页；`bucket/series` 用于顶部趋势（数据驱动，不硬编码）。

## 10. 状态管理

- 单一轻量 store（`state/store.ts`），不引入重型状态库：连接配置、各页数据、长轮询状态、Mock 开关集中于此。
- 数据按 Profile 隔离缓存；切换 Profile 时取消旧轮询、重建连接。
- 刷新类状态（`loading / error / data / lastUpdated`）显式表达，避免数据陈旧被误当实时。
- 密钥不进入 store 的可序列化快照，避免被 devtools/调试输出带走（见 §4）。

## 11. 设计 token 映射

以 CSS custom properties 落地，只使用语义 token，不自创样式（对齐 iOS 设计系统与「有约束力的视觉契约」）。

### 间距
```
--space-1: 4px;  --space-2: 8px;  --space-3: 12px;
--space-4: 16px; --space-5: 24px;
```
用途与 iOS 一致：4 紧邻元素、8 相关内容、12 卡片内部、16 常规内边距、24 区块之间。

### 圆角
```
--radius-badge: 8px;  --radius-card: 12px;
```
小徽标/紧凑控件 8px，卡片 12px；避免描边+阴影叠加的装饰感。

### 颜色与状态（语义色，仅辅助；图标 + 文字共同表达）
| 状态 | 语义色 | 图标（等价 SF Symbols） | 中文标签 |
| --- | --- | --- | --- |
| 正常 | `--color-ok`（绿） | `checkmark.circle.fill` | 正常 |
| 注意 | `--color-warn`（橙） | `exclamationmark.triangle.fill` | 注意 |
| 错误 | `--color-error`（红） | `xmark.circle.fill` | 错误 |
| 中性 / 未知 | `--color-secondary` | `minus.circle` | 未知 |
| 不安全连接 | `--color-warn` | `lock.open.fill` | 不安全（HTTP） |
| 模拟数据 | `--color-secondary` | `play.rectangle` | 模拟数据 |

- 颜色不作为唯一提示；每个状态都配图标 + 中文文字。错误信息给出明确原因与可行操作。
- 深色模式用 `@media (prefers-color-scheme: dark)` 切换语义色变量：**不只是背景变黑**，重点保证重要信息更亮、层级与对比度清晰。
- 直连模式使用 `http://` 时（仅本地开发可行，见 §5），Profile 列表/编辑页显示「不安全（HTTP）」橙色徽章，提示仅在 Tailscale 等私有网络使用。

### 字体与数字
- 数值用 `font-variant-numeric: tabular-nums` 保持刷新时位宽稳定；终端输出、ID、模型名等技术 token 用等宽字体，允许复制/换行，不强行翻译。
- 日期、时间、百分比、数字用 `Intl`（Locale 感知）格式化，不拼接固定地区格式。
- 指标卡片只放一个主要数值、简短标题与可选说明。

### 响应式与无障碍
- 移动端单列或自然换行的两列卡片；桌面/宽屏两至三列网格，相关卡片成组，限制文本区宽度。
- 触控目标至少 44×44px；图标按钮提供中文 `aria-label`，装饰图标 `aria-hidden`。
- 配额进度提供项目名称、使用量、上限、百分比的文本与可访问标签，不只靠颜色/进度条。
- 动效服务交互、短且有用途；`@media (prefers-reduced-motion: reduce)` 下降级为静态状态，不用动画作为唯一反馈。

## 12. 错误处理

- 所有错误路径提供中文文案与可行操作，例如：
  - 网络不可达 → 「无法连接服务器，请检查地址与网络」。
  - 401/403 → 「检查 gateway key / runtime key，或确认 magpie 已开启 Share on local network」；`/api/*` 场景追加「建议固定 `MAGPIE_WEB_KEY`」。
  - CORS 403（直连模式误用） → 「该源不在 magpie 的 Web pages 白名单」。
- 列表局部失败（坏行跳过）用非阻塞提示 + 计数，不整屏报错。
- 密钥/cookie 值一律不进入错误消息、日志、`console` 输出或上报。

## 13. 安全

- **网关零公网暴露**：magpie 始终监听 127.0.0.1，仅 Cloudflare Tunnel 触达，无公网主机名。
- **转发头 + key 校验**：Worker 注入转发头使 magpie 判定 REMOTE，gateway key 恒被校验；**绝不设置 `MAGPIE_TRUST_PROXY=1`**。
- **密钥不落盘**：Worker 对 key 只做逐请求转换，不记录、不缓存、不写日志；浏览器侧按 §4 策略存储并明确警示。
- **Access 登录**：Worker 域名置于 Cloudflare Access 之后，限制访问身份。
- **公开仓库卫生**：文档、Fixture、截图均不含真实主机名/IP/密钥/个人信息；Mock 模式演示无真实密钥。
- **「不安全（HTTP）」徽章**：直连 `http://` Profile 全程可见，提醒仅限私有网络。

## 14. 测试策略（Linux 可运行）

- **Vitest（单元）**：
  - `decode.ts`：未知字段、可选字段、类型漂移（number/字符串）、日期变体、坏行跳过。
  - 请求构造：URL/query/header 断言（含两个自定义 key 头、分页参数）。
  - `longpoll.ts`：fake timers 覆盖 success→loop、timeout、unauthorized→reAuth、networkError 退避、cancel 退出；35s 超时边界。
  - `proxy.ts`：`X-Magpie-Gateway-Key → Bearer、X-Magpie-Web-Key → Cookie` 转换、转发头注入、路径白名单（POST 与未列路由 → 404）、入站 Cookie/Authorization 清理、`Set-Cookie` 剥离、Access JWT 校验失败 → 401、绝不输出 key 到日志。可用 Vitest 直接测 Worker 的 `fetch` handler（或 `@cloudflare/vitest-pool-workers`，待验证）。
- **Playwright（Mock 模式截图）**：
  - 桌面 + 移动视口 × 浅色 + 深色，覆盖概览/动态/Agent/配额/设置。
  - 断言「模拟数据」徽章可见、无网络请求发出（零后端）。
  - 截图产物可作为公开演示素材（均为 Mock 数据，标注 mock）。
- CI（Linux）：`vitest run` 全绿 + Playwright 截图 job，PR 产出截图 artifact。

## 15. 任务分解（T1..Tn）

每条含可观察验收标准（命令/输出）。

- **T1 工程骨架** — Vite + TypeScript + 框架 + Vitest/Playwright 配置。
  验收：`npm run dev` 可启动；`npx vitest run` 占位测试通过。
- **T2 配置/Profile 层** — Profile 模型 + 持久化 + key 存储策略（§4）。
  验收：新增/删除/切换 Profile；刷新后 Profile 仍在；「记住 key / 清除 key」行为正确。
- **T3 模型与容错解码** — §8 全部模型。
  验收：Vitest 模型 Fixture 全绿（含坏行/未知字段/类型漂移用例）。
- **T4 传输抽象 + MockTransport + 模拟数据徽章** — §9 抽象 + §5 Mock。
  验收：开启 Mock，各页显示 Fixture 数据，顶部/角标「模拟数据」徽章，网络请求数为 0。
- **T5 GatewayClient** — usage/requests/quotas/cards/history/route/concurrency/limit/hello。
  验收：单测断言 URL/query/header；`proxy.ts` 单测断言 Bearer 注入与转发头。
- **T6 WebClient + 代理认证** — `/api/*`、`X-Magpie-Web-Key→Cookie`、401/403 重取 key。
  验收：单测覆盖 cookie 转换、转发头、白名单；部署后实测：不带 gateway key 调 `/v1/magpie/quotas` 得 403、`POST /api/...` 得 404、未登录 Access 打不开页面；手动改 key 后触发重认证提示。
- **T7 概览页** — 连接/异常 + 配额摘要 + `/v1/magpie/limit` 展示。
  验收：Mock 模式渲染卡片；断连显示错误并可重试；「不安全（HTTP）」徽章按 Profile 显示。
- **T8 动态页** — Ledger 分页 + 趋势。
  验收：滚动加载下一页；筛选参数正确；`offset/total` 边界处理。
- **T9 Agent 长轮询** — trace 循环 + 取消 + 退避。
  验收：Vitest 状态机全绿；切页/隐藏时请求被取消（无泄漏连接）。
- **T10 Agent 统计** — concurrency/route/quotas/cards 汇总；gateway-only 降级路径。
  验收：路由列表、并发 lane、配额卡渲染；直连模式显示「无全局 trace」提示。
- **T11 服务/Tmux 降级** — 省略 + 可选链接跳转（§2）。
  验收：Profile 配置可选 Web GUI 地址后出现「打开」按钮；未配置则不显示。
- **T12 设计 token + 响应式 + 无障碍** — §11 全部落地。
  验收：桌面/移动布局无裁切；深浅色对比可用；`aria-label` 覆盖图标按钮；44px 触控目标。
- **T13 错误处理与脱敏** — §12。
  验收：所有错误路径有中文文案；日志/控制台无 key/cookie 值。
- **T14 Playwright 截图** — Mock 模式桌面+移动、浅色+深色。
  验收：产出截图 artifact；「模拟数据」徽章可见；零网络请求。
- **T15 CI** — Linux Vitest + Playwright。
  验收：PR 全绿并产出截图 artifact。
- **T16 收尾文档** — README（中英双语：配置说明、Cloudflare 部署、Mock 说明、安全须知）。

## 16. 不要做的事 / 超出范围

- 不在纯浏览器内实现 SSH/PTY（Tmux/服务首版省略或仅外链，见 §2）。
- 不部署/配置 magpie 本身；不写 magpie 配置或数据库。
- 不在 Worker 端持久化、缓存、记录任何密钥。
- 不做全量 agent 会话控制（只读 trace）。
- 不做后台无限轮询；页面隐藏即暂停。
- 不引入重型框架/UI 库/图表库（保持小而一致）。
- 不自创设计样式，只用 token 中存在的值。
- 不在公开仓库中出现真实主机名/IP/密钥/个人信息/私有链接。

## 17. 风险

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 转发头配置错误导致 key 校验失效 | 任意 token 被当 local 接受 | 固定部署清单：绝不设 `MAGPIE_TRUST_PROXY`；`proxy.ts` 单测 + 集成验收覆盖转发头。 |
| Workers VPC / Tunnel 变更（待验证其当前可用性与配额） | 部署路径不可用 | 保留 (c) 自托管同源为备选；实现前用最小样例验证 VPC 绑定。 |
| 浏览器跨源/cookie 限制被误判 | `/api/*` 不可用 | 以 (b) 同源代理为准，直连模式只承诺 gateway-only。 |
| runtime key 明文存于浏览器 | 本机侧泄露 | 默认 `sessionStorage`、显式警告、一键清除；绝不落日志/截图。 |
| 长轮询连接泄漏或误超时 | 资源浪费/漏数据 | 35s 超时、AbortController 取消、隐藏暂停；状态机单测。 |
| magpie API 字段漂移 | 整屏解码失败 | §8 容错解码 + 行级容错。 |
| Mock 演示被误当真实 | 误导 | 全程「模拟数据」徽章 + 截图标注 mock。 |

## 18. 需要用户决策（每项含推荐默认）

1. **托管方案**：选 (b) Cloudflare Worker 代理 + Tunnel（无公网主机名）+ Access。（推荐默认：(b)）
2. **Tunnel 形态**：Workers VPC（`vpc_services` 绑定）或经典「公开隧道主机名 + Access + service token」。（推荐默认：Workers VPC；待验证，若不可用则退回经典方案）
3. **Access 身份源与允许邮箱**：邮箱 OTP / GitHub / Google，以及放行名单。（推荐默认：邮箱 OTP + 由用户提供的白名单邮箱）
4. **自定义域名**：如 `magpie.example.com`（占位，不在此填真实域名）。（推荐默认：用户现有 Cloudflare 域名的子域）
5. **浏览器 key 存储策略**：默认 `sessionStorage`；勾选「记住 key」才写 `localStorage`，附警告与清除按钮。（推荐默认：sessionStorage + opt-in）
6. **key 传递头名**：`X-Magpie-Gateway-Key` / `X-Magpie-Web-Key`（自定义头，仅当次请求）。（推荐默认：沿用这两个名字）
7. **框架**：Preact / Svelte / Lit / vanilla。（推荐默认：Preact）
8. **轮询间隔**：前台默认 20s，可配置（如 10/20/30/60s）；隐藏暂停。（推荐默认：20s）
9. **Tmux/服务**：首版「省略 + 可选链接跳转」；可选中继/agent 二期再评估。（推荐默认：省略 + 外链）
10. **仓库公开策略**：MIT LICENSE，README 中英双语，所有截图/Fixture 均为 Mock，不含真实主机名/密钥。（推荐默认：公开 + MIT）
11. **magpie 主机设置**：开启「Share on local network」、给面板单独建一把只读用途的 gateway key、设置 `MAGPIE_ADDR=127.0.0.1:<port>` 与固定 `MAGPIE_WEB_KEY`。（推荐默认：全部照做；面板只需要只读路由）

> 说明：凡依赖 Cloudflare 产品当前行为或用户私有环境的事实，若未在本文与 API notes 中明确记录，一律视为「待验证」，实现前以最小样例验证。

### Read-only collector dashboard

Profiles may include an optional `collectorUrl` origin/base, validated and exported like
`webGuiUrl`. Set it to this Worker's URL to use server-side authentication, or to a
collector exposed by your own authenticated reverse proxy. The browser app appends
`/v1/collector/…`; it never stores a collector action key. Direct connections must
satisfy browser CORS and HTTPS requirements; the collector itself does not enable CORS.
Mock profiles always use the sanitized local collector fixtures.

The Worker accepts only the listed collector GET endpoints, including explicit pane
capture and registered runtime detail. Configure `COLLECTOR_URL` and the
`COLLECTOR_KEY` Worker secret (read key). The Worker replaces all client credentials,
checks Cloudflare Access, refuses redirects, and returns no-store responses. Actions,
snapshots and collector magpie aggregation paths are outside this allowlist.

Navigation uses `#/home`, `#/activity`, `#/tmux`, `#/agent`, `#/svc`; settings is
available from the header gear. Legacy hashes remain accepted. Collector activity is
the default when configured; the request ledger remains its second sub-view.
Missing host metrics and local runtime quotas stay unavailable rather than being
filled with demo values. Terminal sheets capture every 2.5 seconds while visible,
cancel on close, escape output before rendering ANSI colour, and preserve scroll
position when reading earlier lines. No terminal writes are connected.

Screenshot coverage is defined in `tests/e2e/screenshots.spec.ts` for all five
categories and settings, light/dark, desktop/mobile. Run `npm run screenshots` in
an environment permitted to bind a local preview server.
