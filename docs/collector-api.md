# Collector API v1

Base path `/v1/collector/`. Every response is JSON with `Cache-Control: no-store`. All GETs require `X-Collector-Key` if a read key is configured. POSTs use the separately configured action key in the same header. No CORS allowance or implicit LAN trust. Failure envelope: `{"ok":false,"error":"collection unavailable"}`; status 400 invalid input/action rejection, 401 wrong/missing token, 403 writes disabled/browser Origin, 404 unknown path/id, 405 method, 501 unsupported capture backend, 503 collection/upstream/audit failure.

## Reads / 讀取

| GET suffix | Result / parameters |
|---|---|
| `hello` | name, version, host, caps (endpoint names), readonly |
| `sys` | hostname, updated (Unix seconds), loadavg[3], cpu_count, cpu_usage?, mem, disk, uptime?, goalload |
| `services?scope=all` | updated, services[]; scope user/web/docker/system/all; omitted = all |
| `chart?n=24` | array of actual samples `{t,load?,cpu?,mem?,swap?}`; n 1–24, oldest first |
| `tmux` | updated, summary, sessions[], panes[]; empty/unavailable if tmux absent/no server |
| `tmux/capture?target=%251&lines=300&ansi=1` | ok, target, text, raw (alias), lines_requested, updated; lines 20–2000; ansi=1 preserves terminal escapes |
| `runtimes` | updated, agents[], total_installed, total_running, env_tools |
| `runtimes/{id}` | one registered agent; 404 for unknown id |
| `tasks` | updated, tasks[] from system/user timers and current-user crontab |
| `activity?limit=200` | updated, events[] (local Git only), limit 1–200; newest first |
| `repos` | updated, repos[] from configured roots, no remote git operations |
| `tailscale` | ok, backend_state, version, self, peers[]; unavailable tools return ok=false, unsupported=true |
| `snapshot` | generated_at (UTC ISO 8601), readonly=true, each read dataset above; magpie_* included when configured |
| `magpie/routing` | trace fields plus days/groups/pools, ok, fetched_at |
| `magpie/usage?period=today` | usage summary plus quotas, ok, fetched_at; periods today/7d/30d/all; invalid → today |
| `magpie/providers` | providers payload plus ok, fetched_at; credentials removed |

```json
{"name":"magpie-collector","version":"0.1.0","host":"devbox","caps":["sys","services","chart"],"readonly":true}
```

`caps` in the example is abbreviated. Missing metrics are omitted/null, never synthetic zeros representing success. Sys memory/disk sizes are bytes, uptime seconds, cpu/mem/swap percentages 0–100. CPU is sampled by deltas; the first Linux CPU value is omitted. macOS offers load/memory/disk, with unsupported CPU/swap/uptime omitted. Goalload uses load15 relative to core count: ok below cores, full at cores, over above 1.5× cores; `n=max(0,floor(cores-load15))`. Top process lists use ps CPU lifetime averages and RSS MiB, not instantaneous deltas.

```json
{"updated":1700000000,"services":[{"ip":"127.0.0.1","port":8080,"pids":[123],"name":"devbox","type":"direct","scope":"user","docker_proxy":false,"is_self":false,"res":{"cpu":1.5,"mem_mb":20}}]}
```

Services use Linux listening TCP sockets (`/proc` fallback when ss fails), local PID resource totals, Docker published-port association, and systemd unit rows (port=null). Listener scope without cgroup information is heuristic (ports below 1024 → system). Web scope selects common HTTP/dev ports 80/443/3000/3426/5173/8000/8080/8787. UDP is outside this version. Permissions may hide PIDs. Docker mapping is best effort and does not report container CPU. Missing tooling can return empty lists or unsupported flags; no sudo is attempted.

Tmux sessions have name/windows_count/attached/created/activity/windows[], with nested panes, main_command/main_cwd?, is_agent and attach_cmd where the session identifier is safe. Panes have session/window/index/pane/target/command/cwd?/pid/active/size/preview[]; previews are empty until explicit capture. summary has total/attached/detached/agents/panes_total. No watchdog Goal or resume metadata is invented.

Runtime registry: claude/codex/gemini/opencode/grok/copilot/cursor/aider/goose/crush/kiro/omp. Entries include id/name/installed/bin?/version?/procs/proc_list[]/tasks[]/task_count/meta{sessions_total,sessions_24h}/installable=false. Processes match executable basename; session counts count JSONL files in known session directories, capped at 10,000. No session content, credentials, undocumented local quota files, installs, or cloud probes are read. Missing quota is omitted. Agent-specific detail is the same registry entry, not an invented configuration introspector.

Timers have name/kind=timer/scope/next/last/state/command; next/last currently preserve systemctl JSON microsecond timestamps. Cron entries have kind=cron/scope=user/expr/schedule/command; cron execution history is unavailable. Repos have name/path/branch/branches (count)/commits/dirty (count)/files (count)/size=null/last?; events have repo/sha/short_sha/ts/time/author/subject/text/kind=commit/src=commit/origin=local/branch/files[]. File change lists are empty in this version. At most 100 repositories and 10,000 discovered paths; dependency/build folders and symlinks are skipped. Activity takes up to 200 local commits per repository then globally sorts and limits. It makes no claim about GitHub synchronization.

Tailscale returns only a subset of status JSON: hostname/dns_name/ips/os/online/id, plus peer active/cur_addr/relay/direct/rx_bytes/tx_bytes/last_seen when available. No user directory or private keys. Serve configuration, ping/netcheck and network probes are not exposed.

## Sampling and upstreams / 取樣與代理

A server-owned ring samples every 10 seconds and retains 24 points; starts empty and accumulates real history. Restart clears it. Read caches: sys/services/tasks 10s, tmux 4s (capture uncached), runtimes 10s, tailscale 6s, repos/activity 60s. Slow refreshes are serialized; no background persistent repo index. Version queries currently follow runtime cache. Response timestamps describe each dataset, not an atomic snapshot. Unavailable utilities do not stop other modules.

Magpie uses only configured URL/key, never credential discovery. Authentication is a `magpie_web_<port>` cookie; redirects are refused. Fixed read paths: `/api/gateway/trace?after=0`, `/api/gateway/history`, `/api/groups`, `/api/usage?period=…`, `/api/usage/quotas`, `/api/providers`. Client query parameters besides period are ignored; **asked is never forwarded**. Routing cache 8s, providers 30s, usage today 15s/7d 60s/30d or all 120s. Failed main fetch returns stale cached result retaining fetched_at, or 503 without cache. Failed optional history/groups/quotas marks partial=true. fetched_at is successful aggregation completion time in Unix seconds, not the upstream sample time. Routing preserves upstream order; consumers must select the maximum seq as the current request, never assume routes[0]. No fake rates/latencies/quota values.

Credentials are recursively stripped before responding, including arbitrary nested key/token/secret/password fields (only explicitly masked key values survive). Numeric token usage is retained. Emails/home identities/token-like text are redacted throughout (ANSI decoration is dropped when needed to sanitize split secrets), including terminal output and git text. cwd/cmdline are omitted by default; expose_cmdline enables their redacted forms. This private API still contains operational metadata and is not automatically safe for public publishing. Inspect and further sanitize snapshots before sharing.

## Actions / 動作

POST `/actions/{svc-pause,svc-resume,unit-start,unit-stop,tmux-send,tmux-kill,tmux-new,task-run}`. Actions are disabled unless both allow_actions and action_key are configured. The action token is required even on loopback, using constant-time digest comparison. JSON object only, max 64 KiB, unknown fields rejected. No shell interpolation. Start intent and completion status append to the 0600 audit JSONL file; inability to write intent prevents execution. A failure after execution does not imply rollback.

| Action | Body |
|---|---|
| unit-start / unit-stop | `{unit:"devbox.service",scope:"user"}` |
| svc-pause / svc-resume | same body; systemctl kill STOP/CONT, all unit processes |
| task-run | `{name:"devbox.timer",kind:"timer",scope:"user"}`; starts devbox.service; cron unsupported |
| tmux-send | `{target:"%1",text:"hello",enter:true}` or `{target:"%1",key:"C-c"}` |
| tmux-kill | `{session:"devbox"}` |
| tmux-new | `{name:"devbox",cwd:"/srv/devbox",agent:"codex",prompt:"Describe this project"}`; agent/prompt/cwd optional |

Unit scope defaults to user. Exact `user:devbox.service` or `system:devbox.service` must be in JSON config `units`; task-run checks the resulting service, not the timer. No arbitrary PID/port actions. Tmux target is a bounded identifier; new/kill session names are restricted to letters/digits/underscore/hyphen, max 40. Allowed special keys: Enter/C-c/C-d/Escape/Up/Down/Tab. Text uses literal send-keys; enter is explicit. New cwd, if given, must be within a configured repo root. A registry agent runs via `env` with direct tmux argv (3.2+ required); prompt is one argument, never shell text. Omitting agent creates a default terminal; prompt then is rejected. Success returns `{"ok":true}`. Tmux send is privileged terminal control and can cause command execution, regardless of literal input encoding.
