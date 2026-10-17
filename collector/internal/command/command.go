// Package command runs fixed executables with bounded time and output.
package command

import (
	"context"
	"errors"
	"os/exec"
	"time"
)

type Runner func(context.Context, string, ...string) (string, error)
type bounded struct{ data []byte }

func (b *bounded) Write(p []byte) (int, error) {
	n := len(p)
	if len(b.data)+n > 2<<20 {
		return 0, errors.New("command output exceeds limit")
	}
	b.data = append(b.data, p...)
	return n, nil
}
func Run(ctx context.Context, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.WaitDelay = time.Second
	var out bounded
	cmd.Stdout = &out
	err := cmd.Run()
	return string(out.data), err
}
