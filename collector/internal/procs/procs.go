package procs

import (
	"context"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"magpie-monitor/collector/internal/command"
)

type Process struct {
	Cmdline string  `json:"cmdline,omitempty"`
	CWD     string  `json:"cwd,omitempty"`
	PID     int     `json:"pid"`
	Name    string  `json:"name"`
	CPU     float64 `json:"cpu_pct"`
	Mem     float64 `json:"mem_mb"`
	Elapsed string  `json:"elapsed"`
}

func Parse(s string) []Process {
	out := []Process{}
	for _, l := range strings.Split(s, "\n") {
		f := strings.Fields(l)
		if len(f) < 6 {
			continue
		}
		pid, e := strconv.Atoi(f[0])
		if e != nil {
			continue
		}
		cpu, _ := strconv.ParseFloat(f[1], 64)
		rss, _ := strconv.ParseFloat(f[2], 64)
		cmdline := ""
		if len(f) > 6 {
			cmdline = strings.Join(f[6:], " ")
		}
		out = append(out, Process{PID: pid, Name: f[5], CPU: cpu, Mem: rss / 1024, Elapsed: f[3], Cmdline: cmdline})
	}
	return out
}
func Collect(ctx context.Context, run command.Runner) []Process {
	s, _ := run(ctx, "ps", "-axo", "pid=,pcpu=,rss=,etime=,stat=,comm=,args=")
	out := Parse(s)
	for i := range out {
		out[i].CWD, _ = os.Readlink(filepath.Join("/proc", strconv.Itoa(out[i].PID), "cwd"))
	}
	return out
}
