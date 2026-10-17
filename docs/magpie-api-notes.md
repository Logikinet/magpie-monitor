# magpie API notes (from yetone/magpie source, Go; reference only)
Two HTTP servers: GATEWAY (default 127.0.0.1:3425, Settings' Gateway port) and WEB GUI (magpie web, separate port).

## Auth
- Gateway: `Authorization: Bearer <gateway key>` or `x-api-key: <key>`. Remote (non-local) access only when magpie "Share on local network" is on AND key sent; else 403 JSON error. A "held" key (budget/models/accounts) sees only its own rows; summary /v1/magpie/usage refused for held keys.
- Web GUI (/api/*): guarded by runtime key. Opening `?key=<KEY>` link sets cookie `magpie_web_<port>` (HttpOnly, SameSite=Lax, Path=/; MaxAge 400d if MAGPIE_WEB_KEY fixed, else session). Subsequent requests need that cookie. Key changes on restart unless MAGPIE_WEB_KEY fixed. App: store key in Keychain, do one GET with key to obtain cookie (or send Cookie header `magpie_web_<port>=<key>` directly), re-auth on 401/403.

## Gateway routes (GET unless noted)
- /v1/magpie/usage?period= -> summary (same JSON as web /api/usage)
- /v1/magpie/usage/requests?period=&offset=&limit=&<filters> -> Ledger:
  {callerKeys:[Group], period, rows:[Row], offset, total, bucket, series:[SeriesPoint]}
  Row = Record + {session_role?, cost:float, priced:bool, swapped?, routed?, source?, callerKeyLabel?, agentName, icon, providerName, access?, pricing_model?, computerName?}
  Record keys: operation route_id t agent provider host providerKeyId providerKeyName providerAccount callerKeyId callerKeyName session_provider session_account session_official_login model req served upstream in out ...
  (POST same path = ingest; not for app)
- /v1/magpie/quotas[?kept=1] -> {object:"list", data:[Quota]}
  Quota {provider,name,kind,plan?,user?,windows:[QuotaSpan],balance?,balanceSplit?,error?,asOf?,readDeferred?,readAt?,until?}
  QuotaSpan {name,used,remaining,resetsAt?,unlimited?,display?,amount?,limit?,unit?,pool?,holds?,holdsWhy?}  (5-hour & weekly windows are entries by name)
- /v1/magpie/quotas/cards -> {object:"list", data:[Card]} (cached display cards); POST /v1/magpie/quotas/refresh (rate limited)
- /v1/magpie/quotas/history?days=&provider=&user=
- /v1/magpie/route?session=<id>[&after=<seq>&wait=<secs>] -> {session, seq, route: Route|null}
- /v1/magpie/concurrency -> {object:"concurrency", data:[Lane{busy,waiting,limit,...}], requests, waiting, tools, active}
- /v1/magpie/limit, /api/hello -> {name:"magpie",version}

## Web GUI route (cookie auth)
- /api/gateway/trace?after=<seq>&wait=1 : long-poll; any non-empty wait => server waits up to 25s for seq>after. Response:
  {seq, routes:[Route], totals:{requests,rerouted,errors}, mine:bool, now}
  Route {seq,id,time,agent,parentSession?,session?,usage?[],kind?,model,effort?,tier?,provider,group?,rule?,leadAccount?,subagent?,pinned?,order:[Weighed],...priced}
  Client loop: after=last seq; request timeout >25s (e.g. 35s); cancel Task on tab leave.
- /api/gateway/history?day=YYYY-MM-DD -> {days, routes, cut}

## iOS reference (semantic-craft/iOS-vibebuddy, MIT)
- Uses XcodeGen `project.yml` (iOS 17, local SwiftPM package for shared Kit), builds with `xcodebuild ... CODE_SIGNING_ALLOWED=NO`.
- No SwiftTerm/Citadel usage found. Plan: SwiftTerm (migueldeicaza/SwiftTerm, TerminalView UIKit wrapped in UIViewRepresentable, feed bytes via feed(byteArray:), delegate send(data:) -> SSH stdin, sizeChanged -> pty resize) + Citadel (orlandos-nl/Citadel: SSHClient.connect(host:port:authenticationMethod:.ed25519/.rsa/password, hostKeyValidator:), executeCommand for docker/systemctl, withPTY/withTTY for interactive `tmux attach`).
