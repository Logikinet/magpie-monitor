package repos

import (
	"context"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"magpie-monitor/collector/internal/command"
)

func ParseLog(s, repo, branch string) []map[string]any {
	out := []map[string]any{}
	for _, l := range strings.Split(s, "\n") {
		f := strings.SplitN(l, "\x1f", 4)
		if len(f) != 4 {
			continue
		}
		ts, e := strconv.ParseInt(f[1], 10, 64)
		if e != nil {
			continue
		}
		sha := f[0]
		short := sha
		if len(short) > 8 {
			short = short[:8]
		}
		out = append(out, map[string]any{"repo": repo, "sha": sha, "short_sha": short, "ts": ts, "time": time.Unix(ts, 0).UTC().Format(time.RFC3339), "author": f[2], "subject": f[3], "text": f[3], "kind": "commit", "src": "commit", "origin": "local", "branch": branch, "files": []any{}})
	}
	return out
}
func Discover(roots []string) []string {
	out := []string{}
	seen := map[string]bool{}
	visited := 0
	for _, root := range roots {
		root, _ = filepath.Abs(root)
		_ = filepath.WalkDir(root, func(path string, d os.DirEntry, e error) error {
			visited++
			if visited > 10000 || len(out) >= 100 {
				return filepath.SkipAll
			}
			if e != nil {
				return filepath.SkipDir
			}
			if d.Type()&os.ModeSymlink != 0 {
				return nil
			}
			if !d.IsDir() {
				return nil
			}
			if path != root {
				switch d.Name() {
				case "node_modules", "vendor", ".git", "build", ".build", "dist":
					return filepath.SkipDir
				}
			}
			if _, e := os.Lstat(filepath.Join(path, ".git")); e == nil {
				if !seen[path] {
					seen[path] = true
					out = append(out, path)
				}
				return filepath.SkipDir
			}
			return nil
		})
	}
	return out
}
func Collect(ctx context.Context, run command.Runner, roots []string) (map[string]any, []map[string]any) {
	list := []any{}
	events := []map[string]any{}
	for _, path := range Discover(roots) {
		git := func(args ...string) string {
			s, _ := run(ctx, "git", append([]string{"--no-optional-locks", "-C", path}, args...)...)
			return strings.TrimSpace(s)
		}
		branch := git("branch", "--show-current")
		name := filepath.Base(path)
		log := ParseLog(git("log", "-n", "200", "--format=%H%x1f%ct%x1f%an%x1f%s"), name, branch)
		status := git("status", "--porcelain")
		files := git("ls-files")
		branches := git("branch", "--format=%(refname:short)")
		commits, _ := strconv.Atoi(git("rev-list", "--count", "HEAD"))
		r := map[string]any{"name": name, "path": path, "branch": branch, "branches": count(branches), "commits": commits, "dirty": count(status), "files": count(files), "size": nil}
		if len(log) > 0 {
			r["last"] = log[0]
		}
		list = append(list, r)
		events = append(events, log...)
	}
	sort.SliceStable(events, func(i, j int) bool { return events[i]["ts"].(int64) > events[j]["ts"].(int64) })
	return map[string]any{"updated": time.Now().Unix(), "repos": list}, events
}
func count(s string) int {
	if s == "" {
		return 0
	}
	return len(strings.Split(s, "\n"))
}
