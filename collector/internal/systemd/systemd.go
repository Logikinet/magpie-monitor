package systemd

import (
	"context"
	"strings"

	"magpie-monitor/collector/internal/command"
)

func Parse(s string) []map[string]any {
	out := []map[string]any{}
	for _, l := range strings.Split(s, "\n") {
		f := strings.Fields(strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(l), "●")))
		if len(f) >= 4 && strings.HasSuffix(f[0], ".service") {
			out = append(out, map[string]any{"unit": f[0], "load": f[1], "active": f[2], "sub": f[3], "description": strings.Join(f[4:], " ")})
		}
	}
	return out
}
func Collect(ctx context.Context, run command.Runner, user bool) []map[string]any {
	args := []string{"list-units", "--type=service", "--all", "--no-legend", "--no-pager", "--plain"}
	if user {
		args = append([]string{"--user"}, args...)
	}
	s, _ := run(ctx, "systemctl", args...)
	return Parse(s)
}
