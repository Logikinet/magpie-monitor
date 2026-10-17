package api

import (
	"context"
	"errors"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"magpie-monitor/collector/internal/agents"
	"magpie-monitor/collector/internal/command"
	"magpie-monitor/collector/internal/config"
	"magpie-monitor/collector/internal/docker"
	"magpie-monitor/collector/internal/magpie"
	"magpie-monitor/collector/internal/ports"
	"magpie-monitor/collector/internal/procs"
	"magpie-monitor/collector/internal/repos"
	"magpie-monitor/collector/internal/sys"
	"magpie-monitor/collector/internal/systemd"
	"magpie-monitor/collector/internal/tailscale"
	"magpie-monitor/collector/internal/tasks"
	"magpie-monitor/collector/internal/tmux"
)

type cached struct {
	value any
	at    time.Time
}
type Local struct {
	Config  config.Config
	Run     command.Runner
	Magpie  *magpie.Client
	sampler sys.Sampler
	mu      sync.Mutex
	cache   map[string]cached
	ring    []map[string]any
}

func New(c config.Config) *Local {
	return &Local{Config: c, Run: command.Run, Magpie: &magpie.Client{Base: c.WebURL, Key: c.WebKey}, cache: map[string]cached{}}
}
func (l *Local) Sample(ctx context.Context) {
	v := l.system(ctx)
	l.mu.Lock()
	defer l.mu.Unlock()
	l.cache["sys"] = cached{v, time.Now()}
	l.ring = append(l.ring, sys.Point(v))
	if len(l.ring) > 24 {
		l.ring = l.ring[len(l.ring)-24:]
	}
}
func (l *Local) Start(ctx context.Context) {
	go func() {
		l.Sample(ctx)
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				l.Sample(ctx)
			}
		}
	}()
}
func (l *Local) Collect(ctx context.Context, kind string) (any, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	ttl := 10 * time.Second
	switch kind {
	case "repos", "activity":
		ttl = time.Minute
	case "tailscale":
		ttl = 6 * time.Second
	case "tmux":
		ttl = 4 * time.Second
	case "runtimes":
		ttl = 10 * time.Second
	}
	if v, ok := l.cache[kind]; ok && time.Since(v.at) < ttl {
		return v.value, nil
	}
	var out any
	switch kind {
	case "sys":
		out = l.system(ctx)
	case "chart":
		return append([]map[string]any{}, l.ring...), nil
	case "services":
		v := ports.Collect(ctx, l.Run)
		services := v["services"].([]map[string]any)
		processes := procs.Collect(ctx, l.Run)
		containers := docker.Collect(ctx, l.Run)
		for _, svc := range services {
			mem, cpu := float64(0), float64(0)
			matched := false
			for _, pid := range svc["pids"].([]int) {
				for _, p := range processes {
					if p.PID == pid {
						matched = true
						mem += p.Mem
						cpu += p.CPU
						svc["name"] = filepath.Base(p.Name)
						svc["cmdline"] = p.Cmdline
						svc["cwd"] = p.CWD
					}
				}
			}
			if matched {
				svc["res"] = map[string]any{"mem_mb": mem, "cpu": cpu}
			}
			port := svc["port"].(int)
			for _, c := range containers {
				if dockerHasPort(c["ports"].(string), port) {
					svc["type"] = "docker"
					svc["scope"] = "docker"
					svc["container_id"] = c["container_id"]
					svc["name"] = c["name"]
				}
			}
		}
		for _, user := range []bool{true, false} {
			for _, unit := range systemd.Collect(ctx, l.Run, user) {
				scope := "system"
				if user {
					scope = "user"
				}
				services = append(services, map[string]any{"name": unit["unit"], "unit": unit["unit"], "type": "systemd", "scope": scope, "state": unit["active"], "port": nil, "pids": []int{}})
			}
		}
		markWebServices(services)
		v["services"] = services
		out = v
	case "tmux":
		out = tmux.Collect(ctx, l.Run)
	case "runtimes":
		out = agents.Collect(ctx, l.Run, procs.Collect(ctx, l.Run))
	case "tasks":
		out = tasks.Collect(ctx, l.Run)
	case "repos", "activity":
		r, e := repos.Collect(ctx, l.Run, l.Config.Repos)
		a := map[string]any{"updated": time.Now().Unix(), "events": e}
		l.cache["repos"] = cached{r, time.Now()}
		l.cache["activity"] = cached{a, time.Now()}
		if kind == "repos" {
			out = r
		} else {
			out = a
		}
	case "tailscale":
		out = tailscale.Collect(ctx, l.Run)
	default:
		return nil, errors.New("unknown collector")
	}
	l.cache[kind] = cached{out, time.Now()}
	return out, nil
}
func dockerHasPort(s string, port int) bool {
	for _, m := range publishedPorts.FindAllStringSubmatch(s, -1) {
		if m[1] == intString(port) {
			return true
		}
	}
	return false
}
func top(processes []procs.Process, mem bool) []procs.Process {
	sort.Slice(processes, func(i, j int) bool {
		if mem {
			return processes[i].Mem > processes[j].Mem
		}
		return processes[i].CPU > processes[j].CPU
	})
	if len(processes) > 5 {
		return processes[:5]
	}
	return processes
}
func (l *Local) system(ctx context.Context) map[string]any {
	v := l.sampler.Collect(ctx, l.Run)
	processes := procs.Collect(ctx, l.Run)
	goal := v["goalload"].(map[string]any)
	goal["cpu_top"] = top(append([]procs.Process{}, processes...), false)
	goal["mem_top"] = top(append([]procs.Process{}, processes...), true)
	return v
}
