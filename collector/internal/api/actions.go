package api

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"

	"magpie-monitor/collector/internal/agents"
	"magpie-monitor/collector/internal/tmux"
)

func contains(items []string, item string) bool {
	for _, v := range items {
		if v == item {
			return true
		}
	}
	return false
}
func unitArgs(scope string, args ...string) ([]string, error) {
	if scope == "" || scope == "user" {
		return append([]string{"--user"}, args...), nil
	}
	if scope == "system" {
		return args, nil
	}
	return nil, errors.New("invalid scope")
}
func (l *Local) Action(ctx context.Context, action string, b Action) (any, error) {
	var name string
	var args []string
	switch action {
	case "unit-start", "unit-stop", "svc-pause", "svc-resume", "task-run":
		unit := b.Unit
		if action == "task-run" {
			unit = b.Name
			if b.Kind != "" && b.Kind != "timer" {
				return nil, errors.New("only timers can run")
			}
			unit = strings.TrimSuffix(unit, ".timer") + ".service"
		}
		scope := b.Scope
		if scope == "" {
			scope = "user"
		}
		if !contains(l.Config.Units, scope+":"+unit) {
			return nil, errors.New("unit is not allowlisted")
		}
		if !unitName.MatchString(unit) {
			return nil, errors.New("invalid unit")
		}
		op := "start"
		if action == "unit-stop" {
			op = "stop"
		}
		cmd := []string{op, unit}
		if action == "svc-pause" || action == "svc-resume" {
			signal := "STOP"
			if action == "svc-resume" {
				signal = "CONT"
			}
			cmd = []string{"kill", "--kill-whom=all", "--signal=" + signal, unit}
		}
		var e error
		args, e = unitArgs(scope, cmd...)
		if e != nil {
			return nil, e
		}
		name = "systemctl"
	case "tmux-kill":
		if !tmux.ValidName(b.Session) {
			return nil, errors.New("invalid session")
		}
		name = "tmux"
		args = []string{"kill-session", "-t", "=" + b.Session}
	case "tmux-send":
		if !tmux.ValidTarget(b.Target) {
			return nil, errors.New("invalid target")
		}
		name = "tmux"
		if b.Key != "" {
			if !contains([]string{"Enter", "C-c", "C-d", "Escape", "Up", "Down", "Tab"}, b.Key) {
				return nil, errors.New("invalid key")
			}
			args = []string{"send-keys", "-t", b.Target, b.Key}
		} else {
			args = []string{"send-keys", "-t", b.Target, "-l", "--", b.Text}
		}
	case "tmux-new":
		if !tmux.ValidName(b.Name) {
			return nil, errors.New("invalid session name")
		}
		if b.Agent != "" && !contains(agents.IDs, b.Agent) {
			return nil, errors.New("unknown agent")
		}
		name = "tmux"
		args = []string{"new-session", "-d", "-s", b.Name}
		if b.CWD != "" {
			resolved, e := filepath.EvalSymlinks(b.CWD)
			if e != nil {
				return nil, errors.New("cwd is unavailable")
			}
			info, e := os.Stat(resolved)
			if e != nil || !info.IsDir() {
				return nil, errors.New("cwd is not a directory")
			}
			b.CWD = resolved
			allowed := false
			for _, root := range l.Config.Repos {
				abs, e := filepath.EvalSymlinks(root)
				if e != nil {
					continue
				}
				abs, _ = filepath.Abs(abs)
				rel, e := filepath.Rel(abs, b.CWD)
				if e == nil && rel != ".." && !strings.HasPrefix(rel, "../") && !filepath.IsAbs(rel) {
					allowed = true
				}
			}
			if !allowed {
				return nil, errors.New("cwd must be inside a configured repository root")
			}
			args = append(args, "-c", b.CWD)
		}
		if b.Agent != "" {
			// Two or more command arguments make tmux exec argv directly (tmux >= 3.2).
			// env receives a registry identifier, never a client-supplied command.
			args = append(args, "--", "env", b.Agent)
			if b.Prompt != "" {
				args = append(args, b.Prompt)
			}
		} else if b.Prompt != "" {
			return nil, errors.New("prompt requires a registry agent")
		}

	default:
		return nil, errors.New("unknown action")
	}
	_, err := l.Run(ctx, name, args...)
	if err != nil {
		return nil, errors.New("action command failed")
	}
	if action == "tmux-send" && b.Enter && b.Key == "" {
		if _, err = l.Run(ctx, "tmux", "send-keys", "-t", b.Target, "Enter"); err != nil {
			return nil, errors.New("input sent but Enter failed")
		}
	}
	l.mu.Lock()
	l.cache = map[string]cached{}
	l.mu.Unlock()
	return map[string]any{"ok": true}, nil
}
