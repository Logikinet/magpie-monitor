package tmux

import (
	"context"
	"magpie-monitor/collector/internal/agents"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"magpie-monitor/collector/internal/command"
)

var targetRE = regexp.MustCompile(`^(?:[A-Za-z0-9_][A-Za-z0-9_.:-]{0,99}|%[0-9]{1,10})$`)
var nameRE = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_-]{0,39}$`)

func ValidTarget(s string) bool { return targetRE.MatchString(s) }
func ValidName(s string) bool   { return nameRE.MatchString(s) }
func num(s string) int          { n, _ := strconv.Atoi(s); return n }
func ParseSessions(s string) []map[string]any {
	out := []map[string]any{}
	for _, l := range strings.Split(s, "\n") {
		f := strings.Split(l, "\t")
		if len(f) != 5 {
			continue
		}
		out = append(out, map[string]any{"name": f[0], "windows_count": num(f[1]), "attached": num(f[2]) > 0, "created": num(f[3]), "activity": num(f[4]), "windows": []any{}, "is_agent": false})
	}
	return out
}
func ParsePanes(s string) []map[string]any {
	out := []map[string]any{}
	for _, l := range strings.Split(s, "\n") {
		f := strings.Split(l, "\t")
		if len(f) != 11 {
			continue
		}
		out = append(out, map[string]any{"session": f[0], "window": num(f[1]), "index": num(f[2]), "pane": f[1] + "." + f[2], "target": f[3], "command": f[4], "cwd": f[5], "pid": num(f[6]), "active": f[7] == "1", "size": f[8] + "x" + f[9], "window_name": f[10], "preview": []any{}})
	}
	return out
}
func Collect(ctx context.Context, run command.Runner) map[string]any {
	s, e := run(ctx, "tmux", "list-sessions", "-F", "#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_created}\t#{session_activity}")
	sessions := ParseSessions(s)
	p, _ := run(ctx, "tmux", "list-panes", "-a", "-F", "#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_id}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_pid}\t#{pane_active}\t#{pane_width}\t#{pane_height}\t#{window_name}")
	panes := ParsePanes(p)
	attached := 0
	agentCount := 0
	for _, session := range sessions {
		if session["attached"] == true {
			attached++
		}
		windows := []any{}
		seen := map[int]bool{}
		for _, pane := range panes {
			if pane["session"] != session["name"] {
				continue
			}
			idx := pane["window"].(int)
			if seen[idx] {
				continue
			}
			seen[idx] = true
			wp := []any{}
			for _, p := range panes {
				if p["session"] == session["name"] && p["window"] == idx {
					wp = append(wp, p)
				}
			}
			windows = append(windows, map[string]any{"index": idx, "name": pane["window_name"], "panes": wp, "panes_count": len(wp)})
		}
		session["windows"] = windows
		isAgent := false
		for _, pane := range panes {
			if pane["session"] == session["name"] {
				if _, ok := session["main_command"]; !ok {
					session["main_command"] = pane["command"]
					session["main_cwd"] = pane["cwd"]
				}
				for _, id := range agents.IDs {
					if filepath.Base(pane["command"].(string)) == id {
						isAgent = true
					}
				}
			}
		}
		session["is_agent"] = isAgent
		if isAgent {
			agentCount++
		}
		if name, ok := session["name"].(string); ok && ValidName(name) {
			session["attach_cmd"] = "tmux attach-session -t =" + name
		}

	}
	out := map[string]any{"updated": time.Now().Unix(), "sessions": sessions, "panes": panes, "summary": map[string]any{"total": len(sessions), "attached": attached, "detached": len(sessions) - attached, "panes_total": len(panes), "agents": agentCount}}
	if e != nil {
		out["unavailable"] = true
	}
	return out
}
