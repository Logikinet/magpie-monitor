# Magpie Collector / 主機採集器

Small, dependency-free Go 1.22+ service. Linux uses `/proc`, `ps`, `ss`, and optional local CLIs; macOS uses `sysctl`, `vm_stat`, `ps`, and `df`, with unavailable fields omitted. No sudo, cloud quota calls, installs, git fetches, or deployments.
小型 Go 服務，無第三方依賴。只讀本機資料；缺少工具或權限時回傳空清單、缺省欄位或 unavailable/unsupported。

```sh
cd collector
go build -o magpie-collector ./cmd/magpie-collector
./magpie-collector
# Optional JSON file; environment overrides file values:
./magpie-collector -config config.json
GOCACHE=/tmp/gocache GOPATH=/tmp/gopath go vet ./...
GOCACHE=/tmp/gocache GOPATH=/tmp/gopath go test ./...
```

Read `http://127.0.0.1:8787/v1/collector/hello`. For a protected listener, supply `X-Collector-Key` with the read key. 配置讀取金鑰後，每個 GET 都需要此標頭。

| Environment | Default / purpose |
|---|---|
| `MAGPIE_COLLECTOR_ADDR` | `127.0.0.1:8787` |
| `MAGPIE_COLLECTOR_KEY` | empty; protects every read |
| `MAGPIE_COLLECTOR_ACTION_KEY` | empty; separate write key |
| `MAGPIE_COLLECTOR_ALLOW_ACTIONS` | `false` |
| `MAGPIE_COLLECTOR_EXPOSE_CMDLINE` | `false`; cwd/cmdline remain omitted unless enabled |
| `MAGPIE_COLLECTOR_REPOS` | empty; repository roots, OS path-list separator (`:` on Linux/macOS) |
| `MAGPIE_WEB_URL` | empty; explicit magpie Web GUI base URL |
| `MAGPIE_WEB_KEY` | empty; server-side port-specific cookie only |

JSON keys: `addr`, `key`, `action_key`, `allow_actions`, `expose_cmdline`, `repos` (array), `magpie_web_url`, `magpie_web_key`, `units` (array), `audit_log` (default `collector-audit.jsonl`, relative to working directory). Unknown keys and invalid boolean environment values fail startup. Protect config/env files with mode 0600.

```json
{
  "addr": "127.0.0.1:8787",
  "repos": ["/srv/devbox"],
  "units": ["user:devbox.service"],
  "audit_log": "/srv/collector/actions.jsonl"
}
```

## Security / 安全模型

Writes require **both** `allow_actions=true` and a nonempty action key, then that key in `X-Collector-Key`. The read key grants no write access. Unit actions require an exact `user:unit.service` or `system:unit.service` allowlist entry; task-run checks the resulting service. Service pause/resume signals the allowlisted systemd unit, rather than accepting arbitrary PIDs or ports. No privilege escalation. Tmux input can execute commands inside the terminal: grant the action key only to trusted operators. Agent launches require tmux 3.2+ for direct argv execution.

寫入預設關閉，需同時開關、動作金鑰及單元允許清單。所有程序以目前使用者權限執行；不會使用 sudo。非 loopback 綁定必須同時提供 `-allow-remote` 和讀取金鑰。HTTP 本身不加密，遠端使用應置於受信任的 TLS/SSH 通道後。

Commands have five-second deadlines, a two-MiB output bound, and no shell interpolation. JSON actions are limited to 64 KiB; browser Origin headers are rejected. Before executing an action, the collector must append to its 0600 JSONL audit file; the completion status is appended too. Denied authentication attempts are logged without credentials or request text.

Responses recursively remove credential fields, preserve only explicitly masked keys, redact emails/home identities/token-like text, and omit cwd/cmdline by default. This is **not** a complete public-data classifier: git subjects, tmux text, names, network addresses, and repository paths may still be sensitive. `/snapshot` is a private export suitable as input to a separately reviewed static publishing pipeline, not an automatic publisher.

回應會脫敏，但公開前仍須檢查快照；尤其終端輸出、Git 說明、主機與網路位址。此程式不包含發布或部署功能。本地額度因無已知且有文件支持的用量檔案格式而省略，不讀認證檔。

See [API contract](../docs/collector-api.md) and [development commands](../docs/dev-run.md). Install the [example user unit](deploy/magpie-collector.service) after adapting its absolute paths; keep credentials in its protected environment file.
