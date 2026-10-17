package agents

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"magpie-monitor/collector/internal/command"
	"magpie-monitor/collector/internal/procs"
)

var IDs = []string{"claude", "codex", "gemini", "opencode", "grok", "copilot", "cursor", "aider", "goose", "crush", "kiro", "omp"}

func Collect(ctx context.Context, run command.Runner, processes []procs.Process) map[string]any {
	out := []any{}
	installed, running := 0, 0
	home, _ := os.UserHomeDir()
	for _, id := range IDs {
		bin, e := exec.LookPath(id)
		v := map[string]any{"id": id, "name": id, "installed": e == nil, "tasks": []any{}, "task_count": 0, "installable": false}
		if e == nil {
			installed++
			v["bin"] = bin
			version, err := run(ctx, bin, "--version")
			if err == nil {
				v["version"] = strings.TrimSpace(version)
			}
		}
		p := []procs.Process{}
		for _, proc := range processes {
			if Matches(proc, id) {
				p = append(p, proc)
			}
		}
		v["procs"] = len(p)
		v["proc_list"] = p
		running += len(p)
		total, recent := 0, 0
		// Count directory entries only; never read session transcripts or credentials.
		dir := ""
		switch id {
		case "claude":
			dir = filepath.Join(home, ".claude", "projects")
		case "codex":
			dir = filepath.Join(home, ".codex", "sessions")
		case "gemini":
			dir = filepath.Join(home, ".gemini", "tmp")
		}
		if dir != "" {
			_ = filepath.WalkDir(dir, func(path string, d os.DirEntry, e error) error {
				if e != nil {
					return filepath.SkipDir
				}
				if total >= 10000 {
					return filepath.SkipAll
				}
				if d.Type()&os.ModeSymlink != 0 {
					return nil
				}
				if !d.IsDir() && strings.HasSuffix(path, ".jsonl") {
					total++
					if info, e := d.Info(); e == nil && time.Since(info.ModTime()) < 24*time.Hour {
						recent++
					}
				}
				return nil
			})
		}
		v["meta"] = map[string]any{"sessions_total": total, "sessions_24h": recent}
		out = append(out, v)
	}
	return map[string]any{"updated": time.Now().Unix(), "agents": out, "total_installed": installed, "total_running": running, "env_tools": map[string]any{}}
}

func Matches(p procs.Process, id string) bool {
	if filepath.Base(p.Name) == id {
		return true
	}
	fields := strings.Fields(p.Cmdline)
	// Only inspect executable positions, never arbitrary prompt text.
	for i := 0; i < len(fields) && i < 2; i++ {
		name := strings.TrimSuffix(filepath.Base(fields[i]), ".js")
		if name == id {
			return true
		}
	}
	return false
}
