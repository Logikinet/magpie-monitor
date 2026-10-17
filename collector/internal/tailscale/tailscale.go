package tailscale

import (
	"context"
	"encoding/json"
	"sort"

	"magpie-monitor/collector/internal/command"
)

func node(n map[string]any) map[string]any {
	out := map[string]any{}
	for src, dst := range map[string]string{"ID": "id", "HostName": "hostname", "DNSName": "dns_name", "TailscaleIPs": "ips", "OS": "os", "Online": "online", "Active": "active", "CurAddr": "cur_addr", "Relay": "relay", "RxBytes": "rx_bytes", "TxBytes": "tx_bytes", "LastSeen": "last_seen"} {
		if v, ok := n[src]; ok {
			out[dst] = v
		}
	}
	if addr, ok := n["CurAddr"].(string); ok {
		out["direct"] = addr != ""
	}
	return out
}
func Parse(s string) (map[string]any, error) {
	var raw map[string]any
	if e := json.Unmarshal([]byte(s), &raw); e != nil {
		return nil, e
	}
	peers := []any{}
	if m, ok := raw["Peer"].(map[string]any); ok {
		keys := []string{}
		for k := range m {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			if p, ok := m[k].(map[string]any); ok {
				peers = append(peers, node(p))
			}
		}
	}
	out := map[string]any{"ok": true, "backend_state": raw["BackendState"], "version": raw["Version"], "peers": peers}
	if n, ok := raw["Self"].(map[string]any); ok {
		out["self"] = node(n)
	}
	return out, nil
}
func Collect(ctx context.Context, run command.Runner) map[string]any {
	s, e := run(ctx, "tailscale", "status", "--json")
	if e == nil {
		if v, e := Parse(s); e == nil {
			return v
		}
	}
	return map[string]any{"ok": false, "unsupported": true, "peers": []any{}}
}
