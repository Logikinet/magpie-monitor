package agents

import (
	"magpie-monitor/collector/internal/procs"
	"testing"
)

func TestProcessMatch(t *testing.T) {
	for _, c := range []struct {
		p    procs.Process
		want bool
	}{{procs.Process{Name: "/usr/bin/codex"}, true}, {procs.Process{Name: "node", Cmdline: "node /opt/tools/codex.js --version"}, true}, {procs.Process{Name: "bash", Cmdline: "bash -c echo codex"}, false}} {
		if Matches(c.p, "codex") != c.want {
			t.Fatal(c)
		}
	}
}
