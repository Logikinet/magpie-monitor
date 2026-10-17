package api

import (
	"context"
	"errors"
	"strconv"
	"time"

	"magpie-monitor/collector/internal/tmux"
)

func (l *Local) Capture(ctx context.Context, target string, lines int, ansi bool) (any, error) {
	if !tmux.ValidTarget(target) || lines < 20 || lines > 2000 {
		return nil, errors.New("invalid capture")
	}
	args := []string{"capture-pane", "-p", "-t", target, "-S", "-" + strconv.Itoa(lines)}
	if ansi {
		args = append(args, "-e")
	}
	text, e := l.Run(ctx, "tmux", args...)
	return map[string]any{"text": text, "raw": text, "target": target, "lines_requested": lines, "updated": time.Now().Unix(), "ok": e == nil}, e
}
