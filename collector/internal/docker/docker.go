package docker

import (
	"context"
	"encoding/json"
	"strings"

	"magpie-monitor/collector/internal/command"
)

func Parse(s string) []map[string]any {
	out := []map[string]any{}
	for _, l := range strings.Split(s, "\n") {
		var v struct{ ID, Names, Ports, Status string }
		if json.Unmarshal([]byte(l), &v) == nil && v.ID != "" {
			out = append(out, map[string]any{"container_id": v.ID, "name": v.Names, "ports": v.Ports, "status": v.Status})
		}
	}
	return out
}
func Collect(ctx context.Context, run command.Runner) []map[string]any {
	s, _ := run(ctx, "docker", "ps", "--format", "{{json .}}")
	return Parse(s)
}
