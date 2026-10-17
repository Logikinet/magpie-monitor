package sys

import (
	"context"
	"encoding/json"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"magpie-monitor/collector/internal/command"
)

type Sampler struct {
	mu                  sync.Mutex
	lastTotal, lastIdle uint64
}

func number(s string) float64 { n, _ := strconv.ParseFloat(s, 64); return n }
func ParseMem(s string) map[string]any {
	m := map[string]float64{}
	for _, l := range strings.Split(s, "\n") {
		f := strings.Fields(l)
		if len(f) > 1 {
			m[strings.TrimSuffix(f[0], ":")] = number(f[1]) * 1024
		}
	}
	total := m["MemTotal"]
	if total <= 0 {
		return map[string]any{}
	}
	available := m["MemAvailable"]
	if available == 0 {
		available = m["MemFree"] + m["Buffers"] + m["Cached"]
	}
	used := total - available
	swap := m["SwapTotal"] - m["SwapFree"]
	out := map[string]any{"total": total, "used": used, "available": available, "swap_total": m["SwapTotal"], "swap_used": swap}
	if total > 0 {
		out["percent"] = 100 * used / total
	}
	if m["SwapTotal"] > 0 {
		out["swap_percent"] = 100 * swap / m["SwapTotal"]
	}
	return out
}
func ParseCPU(s string) (total, idle uint64) {
	for _, l := range strings.Split(s, "\n") {
		f := strings.Fields(l)
		if len(f) > 4 && f[0] == "cpu" {
			for i := 1; i < len(f) && i <= 8; i++ {
				n, _ := strconv.ParseUint(f[i], 10, 64)
				total += n
				if i == 4 || i == 5 {
					idle += n
				}
			}
			break
		}
	}
	return
}
func ParseLoad(s string) []float64 {
	f := strings.Fields(strings.NewReplacer("{", "", "}", "").Replace(s))
	out := []float64{}
	for i := 0; i < len(f) && i < 3; i++ {
		out = append(out, number(f[i]))
	}
	return out
}
func (s *Sampler) Collect(ctx context.Context, run command.Runner) map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	host, _ := os.Hostname()
	out := map[string]any{"hostname": host, "cpu_count": runtime.NumCPU(), "updated": time.Now().Unix(), "disk": nil}
	read := func(p string) string { b, _ := os.ReadFile(p); return string(b) }
	if runtime.GOOS == "linux" {
		out["mem"] = ParseMem(read("/proc/meminfo"))
		out["loadavg"] = ParseLoad(read("/proc/loadavg"))
		u := strings.Fields(read("/proc/uptime"))
		if len(u) > 0 {
			out["uptime"] = number(u[0])
		}
		total, idle := ParseCPU(read("/proc/stat"))
		if s.lastTotal > 0 && total > s.lastTotal && idle >= s.lastIdle {
			out["cpu_usage"] = 100 * (1 - float64(idle-s.lastIdle)/float64(total-s.lastTotal))
		}
		s.lastTotal, s.lastIdle = total, idle
	} else if runtime.GOOS == "darwin" {
		if v, e := run(ctx, "sysctl", "-n", "vm.loadavg"); e == nil {
			out["loadavg"] = ParseLoad(v)
		}
		if v, e := run(ctx, "sysctl", "-n", "hw.memsize"); e == nil {
			out["mem"] = map[string]any{"total": number(strings.TrimSpace(v))}
		}
		if v, e := run(ctx, "vm_stat"); e == nil {
			out["mem"] = ParseVM(v, out["mem"])
		}
	}
	if v, e := run(ctx, "df", "-Pk", "/"); e == nil {
		lines := strings.Split(strings.TrimSpace(v), "\n")
		if len(lines) > 1 {
			f := strings.Fields(lines[len(lines)-1])
			if len(f) >= 6 {
				out["disk"] = map[string]any{"total": number(f[1]) * 1024, "used": number(f[2]) * 1024, "free": number(f[3]) * 1024, "percent": number(strings.TrimSuffix(f[4], "%"))}
			}
		}
	}
	goal := map[string]any{"cores": runtime.NumCPU(), "cpu_top": []any{}, "mem_top": []any{}}
	if l, ok := out["loadavg"].([]float64); ok && len(l) == 3 {
		load := l[2]
		cores := float64(runtime.NumCPU())
		zone := "ok"
		n := int(cores - load)
		if n < 0 {
			n = 0
		}
		if load >= cores {
			zone = "full"
		}
		if load > cores*1.5 {
			zone = "over"
		}
		goal["load15"] = load
		goal["zone"] = zone
		goal["n"] = n
	}
	out["goalload"] = goal
	return out
}
func ParseVM(s string, existing any) map[string]any {
	m, ok := existing.(map[string]any)
	if !ok {
		m = map[string]any{}
	}
	page := float64(4096)
	for _, l := range strings.Split(s, "\n") {
		if strings.Contains(l, "page size of") {
			f := strings.Fields(l)
			for i, v := range f {
				if v == "of" && i+1 < len(f) {
					page = number(f[i+1])
				}
			}
		}
	}
	free := float64(0)
	for _, l := range strings.Split(s, "\n") {
		parts := strings.SplitN(l, ":", 2)
		if len(parts) == 2 && (parts[0] == "Pages free" || parts[0] == "Pages inactive" || parts[0] == "Pages speculative") {
			free += number(strings.TrimSuffix(strings.TrimSpace(parts[1]), ".")) * page
		}
	}
	if t, ok := m["total"].(float64); ok && t > 0 {
		m["available"] = free
		m["used"] = t - free
		m["percent"] = (t - free) * 100 / t
	}
	return m
}
func Point(v map[string]any) map[string]any {
	p := map[string]any{"t": time.Now().UnixMilli()}
	if x, ok := v["cpu_usage"]; ok {
		p["cpu"] = x
	}
	if l, ok := v["loadavg"].([]float64); ok && len(l) > 0 {
		p["load"] = l[0]
	}
	if m, ok := v["mem"].(map[string]any); ok {
		p["mem"] = m["percent"]
		p["swap"] = m["swap_percent"]
	}
	return p
}

// Normalize converts typed containers to the JSON representation used at API boundaries.
func Normalize(v any) any {
	b, _ := json.Marshal(v)
	var out any
	_ = json.Unmarshal(b, &out)
	return out
}
