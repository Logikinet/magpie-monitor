# magpie-web

## 中文

magpie-web 是 yetone/magpie LLM 网关的 Web 监控伴侣，与 iOS 应用 [Logikinet/magpie-ios](https://github.com/Logikinet/magpie-ios) 配套。它提供只读的网关状态、请求活动、Agent 路由与配额面板。

### 功能

- 概览、请求动态、Agent trace 与并发、配额、Profile 设置。
- Live 代理、Direct 直连和 Mock 模拟模式。
- 桌面与移动端适配，支持浅色和深色外观。

### 截图

下列所有截图均使用模拟数据（Mock data）。

| 页面  | 桌面浅色                                                                             | 桌面深色                                                                            | 移动浅色                                                                            | 移动深色                                                                           |
| ----- | ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| 概览  | ![概览桌面浅色（模拟数据 / Mock data）](docs/screenshots/overview-desktop-light.png) | ![概览桌面深色（模拟数据 / Mock data）](docs/screenshots/overview-desktop-dark.png) | ![概览移动浅色（模拟数据 / Mock data）](docs/screenshots/overview-mobile-light.png) | ![概览移动深色（模拟数据 / Mock data）](docs/screenshots/overview-mobile-dark.png) |
| 动态  | ![动态桌面浅色（模拟数据 / Mock data）](docs/screenshots/activity-desktop-light.png) | ![动态桌面深色（模拟数据 / Mock data）](docs/screenshots/activity-desktop-dark.png) | ![动态移动浅色（模拟数据 / Mock data）](docs/screenshots/activity-mobile-light.png) | ![动态移动深色（模拟数据 / Mock data）](docs/screenshots/activity-mobile-dark.png) |
| Agent | ![Agent 桌面浅色（模拟数据 / Mock data）](docs/screenshots/agent-desktop-light.png)  | ![Agent 桌面深色（模拟数据 / Mock data）](docs/screenshots/agent-desktop-dark.png)  | ![Agent 移动浅色（模拟数据 / Mock data）](docs/screenshots/agent-mobile-light.png)  | ![Agent 移动深色（模拟数据 / Mock data）](docs/screenshots/agent-mobile-dark.png)  |
| 配额  | ![配额桌面浅色（模拟数据 / Mock data）](docs/screenshots/quotas-desktop-light.png)   | ![配额桌面深色（模拟数据 / Mock data）](docs/screenshots/quotas-desktop-dark.png)   | ![配额移动浅色（模拟数据 / Mock data）](docs/screenshots/quotas-mobile-light.png)   | ![配额移动深色（模拟数据 / Mock data）](docs/screenshots/quotas-mobile-dark.png)   |
| 设置  | ![设置桌面浅色（模拟数据 / Mock data）](docs/screenshots/settings-desktop-light.png) | ![设置桌面深色（模拟数据 / Mock data）](docs/screenshots/settings-desktop-dark.png) | ![设置移动浅色（模拟数据 / Mock data）](docs/screenshots/settings-mobile-light.png) | ![设置移动深色（模拟数据 / Mock data）](docs/screenshots/settings-mobile-dark.png) |

### 连接模式

- **Live**：同源 Cloudflare Worker 代理，支持网关 API 与全局 Agent trace。
- **Direct**：浏览器直接访问网关，仅支持 gateway API；需要 HTTPS，并把页面来源加入 magpie「Settings → Network and sharing → Web pages」白名单。Agent 仅能按会话查看路由。
- **Mock**：读取本地脱敏 fixture，完全不发网络请求；始终显示「模拟数据」标记。通过 `/?mock=1` 打开。

### 安全模型

- 推荐 Worker proxy + Workers VPC + Cloudflare Access；magpie 不暴露公网。
- 每次请求分别携带 gateway key 和 web key；Worker 按路由转换为 Bearer 或 `magpie_web_<port>` cookie，并清除原始 key 头。
- Worker 注入转发头以确保 magpie 执行远程请求的 key 校验。**绝不设置 `MAGPIE_TRUST_PROXY`**。
- magpie 建议绑定 `MAGPIE_ADDR=127.0.0.1:<port>`。
- Key 默认只存于 `sessionStorage`；选择「记住 key」才存入浏览器 `localStorage`，该选项会以明文保存在浏览器配置中。可随时清除。
- Profile 导出不包含密钥。Worker 不应记录、缓存或持久化任何 key。

### 开发

```sh
npm install
npm run dev
npm test
npm run build
npx playwright install chromium
npm run screenshots
```

访问 `http://localhost:5173/?mock=1` 查看模拟数据。

### 部署（尚未完成）

- [ ] 创建 Cloudflare Tunnel / Workers VPC 服务。
- [ ] 配置 Workers VPC services。
- [ ] 填写 `wrangler.jsonc` 中的占位配置。
- [ ] 创建 Cloudflare Access 应用和访问策略。
- [ ] 执行 `wrangler deploy`。
- [ ] 验证无 key 请求返回 403、POST 请求返回 404/405，且页面必须通过 Access 登录。

全部域名示例均使用 `magpie.example.com` 占位。

### 范围

浏览器端不提供 Tmux 或服务管理；请继续使用 iOS 应用完成这些操作。

### 许可与致谢

MIT。感谢 [yetone/magpie](https://github.com/yetone/magpie)、Preact 与 Vite。

## English

magpie-web is a web monitoring companion for the yetone/magpie LLM gateway, alongside the iOS app [Logikinet/magpie-ios](https://github.com/Logikinet/magpie-ios). It provides read-only gateway status, request activity, Agent routing, and quota views.

### Features

- Overview, request activity, Agent traces and concurrency, quotas, and Profile settings.
- Live proxy, Direct connection, and Mock data modes.
- Responsive desktop and mobile layouts with light and dark themes.

### Screenshots

All screenshots below use mock data.

| Page     | Desktop light                                                                      | Desktop dark                                                                     | Mobile light                                                                     | Mobile dark                                                                    |
| -------- | ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Overview | ![Overview desktop light (Mock data)](docs/screenshots/overview-desktop-light.png) | ![Overview desktop dark (Mock data)](docs/screenshots/overview-desktop-dark.png) | ![Overview mobile light (Mock data)](docs/screenshots/overview-mobile-light.png) | ![Overview mobile dark (Mock data)](docs/screenshots/overview-mobile-dark.png) |
| Activity | ![Activity desktop light (Mock data)](docs/screenshots/activity-desktop-light.png) | ![Activity desktop dark (Mock data)](docs/screenshots/activity-desktop-dark.png) | ![Activity mobile light (Mock data)](docs/screenshots/activity-mobile-light.png) | ![Activity mobile dark (Mock data)](docs/screenshots/activity-mobile-dark.png) |
| Agent    | ![Agent desktop light (Mock data)](docs/screenshots/agent-desktop-light.png)       | ![Agent desktop dark (Mock data)](docs/screenshots/agent-desktop-dark.png)       | ![Agent mobile light (Mock data)](docs/screenshots/agent-mobile-light.png)       | ![Agent mobile dark (Mock data)](docs/screenshots/agent-mobile-dark.png)       |
| Quotas   | ![Quotas desktop light (Mock data)](docs/screenshots/quotas-desktop-light.png)     | ![Quotas desktop dark (Mock data)](docs/screenshots/quotas-desktop-dark.png)     | ![Quotas mobile light (Mock data)](docs/screenshots/quotas-mobile-light.png)     | ![Quotas mobile dark (Mock data)](docs/screenshots/quotas-mobile-dark.png)     |
| Settings | ![Settings desktop light (Mock data)](docs/screenshots/settings-desktop-light.png) | ![Settings desktop dark (Mock data)](docs/screenshots/settings-desktop-dark.png) | ![Settings mobile light (Mock data)](docs/screenshots/settings-mobile-light.png) | ![Settings mobile dark (Mock data)](docs/screenshots/settings-mobile-dark.png) |

### Connection modes

- **Live**: same-origin Cloudflare Worker proxy for gateway APIs and global Agent traces.
- **Direct**: the browser connects to the gateway and supports gateway APIs only. HTTPS is required, and the site origin must be added under magpie **Settings → Network and sharing → Web pages**. Agent view is limited to per-session routes.
- **Mock**: uses local sanitized fixtures with zero network requests and always shows a Mock data badge. Open `/?mock=1`.

### Security model

- The recommended setup is a Worker proxy + Workers VPC + Cloudflare Access, with magpie kept off the public internet.
- Each request carries separate gateway and web keys. The Worker converts them to a Bearer token or `magpie_web_<port>` cookie and removes the original key headers.
- The Worker injects forwarding headers so magpie applies remote-request key validation. **Never set `MAGPIE_TRUST_PROXY`.**
- Bind magpie using `MAGPIE_ADDR=127.0.0.1:<port>`.
- Keys use `sessionStorage` by default. Opting into “Remember key” stores them in browser `localStorage` in plaintext; they can be cleared at any time.
- Profile exports exclude keys. The Worker must not log, cache, or persist keys.

### Development

```sh
npm install
npm run dev
npm test
npm run build
npx playwright install chromium
npm run screenshots
```

Open `http://localhost:5173/?mock=1` to view mock data.

### Deployment (not yet done)

- [ ] Create a Cloudflare Tunnel / Workers VPC service.
- [ ] Configure Workers VPC services.
- [ ] Fill the placeholders in `wrangler.jsonc`.
- [ ] Create a Cloudflare Access application and access policy.
- [ ] Run `wrangler deploy`.
- [ ] Verify that a request without a key returns 403, POST returns 404/405, and Access login is required.

Use the placeholder domain `magpie.example.com` in examples.

### Scope

Tmux and service management are not included in the browser app; use the iOS app for those tasks.

### License and credits

MIT. Thanks to [yetone/magpie](https://github.com/yetone/magpie), Preact, and Vite.
