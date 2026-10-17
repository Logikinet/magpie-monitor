package tasks

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"magpie-monitor/collector/internal/command"
)

func ParseTimers(s, scope string) []map[string]any {
	var rows []map[string]any
	if json.Unmarshal([]byte(s), &rows) != nil {
		return []map[string]any{}
	}
	out := []map[string]any{}
	for _, r := range rows {
		unit, _ := r["unit"].(string)
		if !strings.HasSuffix(unit, ".timer") {
			continue
		}
		out = append(out, map[string]any{"name": unit, "kind": "timer", "scope": scope, "next": r["next"], "last": r["last"], "state": "scheduled", "command": r["activates"]})
	}
	return out
}
func ParseCron(s string) []map[string]any {
	out := []map[string]any{}
	for _, l := range strings.Split(s, "\n") {
		l = strings.TrimSpace(l)
		if l == "" || strings.HasPrefix(l, "#") {
			continue
		}
		f := strings.Fields(l)
		count := 5
		if strings.HasPrefix(l, "@") {
			count = 1
		}
		if len(f) <= count || strings.Contains(f[0], "=") {
			continue
		}
		out = append(out, map[string]any{"name": "cron", "kind": "cron", "scope": "user", "expr": strings.Join(f[:count], " "), "schedule": strings.Join(f[:count], " "), "command": strings.Join(f[count:], " ")})
	}
	return out
}
func Collect(ctx context.Context, run command.Runner) map[string]any {
	out := []map[string]any{}
	for _, scope := range []string{"user", "system"} {
		args := []string{"list-timers", "--all", "--no-pager", "--output=json"}
		if scope == "user" {
			args = append([]string{"--user"}, args...)
		}
		s, _ := run(ctx, "systemctl", args...)
		out = append(out, ParseTimers(s, scope)...)
	}
	s, _ := run(ctx, "crontab", "-l")
	out = append(out, ParseCron(s)...)
	return map[string]any{"updated": time.Now().Unix(), "tasks": out}
}
