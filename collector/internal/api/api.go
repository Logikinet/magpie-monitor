package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"magpie-monitor/collector/internal/auth"
	"magpie-monitor/collector/internal/config"
	"magpie-monitor/collector/internal/redact"
	"magpie-monitor/collector/internal/sys"
	"magpie-monitor/collector/internal/tmux"
)

const Prefix = "/v1/collector/"
const Version = "0.1.0"

var publishedPorts = regexp.MustCompile(`:(\d+)->`)
var unitName = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_.@:-]*\.service$`)
var tmuxActionName = regexp.MustCompile(`^[A-Za-z0-9_.:%-]+$`)

func intString(n int) string { return strconv.Itoa(n) }

type Action struct {
	Prompt  string `json:"prompt"`
	Unit    string `json:"unit"`
	Scope   string `json:"scope"`
	Name    string `json:"name"`
	Kind    string `json:"kind"`
	Target  string `json:"target"`
	Session string `json:"session"`
	Text    string `json:"text"`
	Key     string `json:"key"`
	Enter   bool   `json:"enter"`
	CWD     string `json:"cwd"`
	Agent   string `json:"agent"`
}
type Backend interface {
	Collect(context.Context, string) (any, error)
	Action(context.Context, string, Action) (any, error)
}
type Proxy interface {
	Get(context.Context, string, string) (map[string]any, error)
}
type Server struct {
	Config  config.Config
	Backend Backend
	Proxy   Proxy
	auditMu sync.Mutex
}

var parts = []string{"sys", "services", "chart", "tmux", "runtimes", "tasks", "activity", "repos", "tailscale"}

func (s *Server) write(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(redact.Value(sys.Normalize(v), s.Config.ExposeCmdline, s.Config.Key, s.Config.ActionKey, s.Config.WebKey))
}
func (s *Server) fail(w http.ResponseWriter, status int, msg string) {
	s.write(w, status, map[string]any{"ok": false, "error": msg})
}
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if !strings.HasPrefix(r.URL.Path, Prefix) {
		s.fail(w, 404, "not found")
		return
	}
	p := strings.TrimPrefix(r.URL.Path, Prefix)
	if strings.HasPrefix(p, "actions/") {
		s.action(w, r, strings.TrimPrefix(p, "actions/"))
		return
	}
	if s.Config.Key != "" && !auth.Match(s.Config.Key, r.Header.Get("X-Collector-Key")) {
		s.fail(w, 401, "read token required")
		return
	}
	if r.Method != "GET" {
		s.fail(w, 405, "GET required")
		return
	}
	if p == "hello" {
		host, _ := os.Hostname()
		caps := append(append([]string{}, parts...), "tmux/capture", "snapshot", "magpie/routing", "magpie/usage", "magpie/providers")
		if s.Config.Writable() {
			caps = append(caps, "actions/svc-pause", "actions/svc-resume", "actions/unit-start", "actions/unit-stop", "actions/tmux-send", "actions/tmux-kill", "actions/tmux-new", "actions/tmux-wake", "actions/task-run", "actions/quota-refresh")
		}
		s.write(w, 200, map[string]any{"name": "magpie-collector", "version": Version, "host": host, "caps": caps, "readonly": !s.Config.Writable()})
		return
	}
	if p == "tmux/capture" {
		target := r.URL.Query().Get("target")
		if !tmux.ValidTarget(target) {
			s.fail(w, 400, "invalid target")
			return
		}
		n, e := boundedInt(r.URL.Query().Get("lines"), 300, 20, 2000)
		if e != nil {
			s.fail(w, 400, e.Error())
			return
		}
		local, ok := s.Backend.(interface {
			Capture(context.Context, string, int, bool) (any, error)
		})
		if !ok {
			s.fail(w, 501, "capture unavailable")
			return
		}
		v, e := local.Capture(r.Context(), target, n, r.URL.Query().Get("ansi") == "1")
		s.result(w, v, e)
		return
	}
	if strings.HasPrefix(p, "magpie/") {
		kind := strings.TrimPrefix(p, "magpie/")
		if !contains([]string{"routing", "usage", "providers"}, kind) {
			s.fail(w, 404, "not found")
			return
		}
		if s.Proxy == nil {
			s.fail(w, 503, "magpie unavailable")
			return
		}
		v, e := s.Proxy.Get(r.Context(), kind, r.URL.Query().Get("period"))
		s.result(w, v, e)
		return
	}
	if p == "snapshot" {
		v := map[string]any{"generated_at": time.Now().UTC().Format(time.RFC3339), "readonly": true}
		for _, part := range parts {
			data, e := s.Backend.Collect(r.Context(), part)
			if e != nil {
				v[part] = map[string]any{"ok": false, "error": "collection unavailable"}
			} else {
				v[part] = data
			}
		}
		if s.Proxy != nil && s.Config.WebURL != "" {
			for _, kind := range []string{"routing", "usage", "providers"} {
				data, e := s.Proxy.Get(r.Context(), kind, "today")
				if e == nil {
					v["magpie_"+kind] = data
				} else {
					v["magpie_"+kind] = map[string]any{"ok": false, "error": "upstream unavailable"}
				}
			}
		}
		s.write(w, 200, v)
		return
	}
	kind := p
	if strings.HasPrefix(p, "runtimes/") {
		kind = "runtimes"
	}
	if !contains(parts, kind) {
		s.fail(w, 404, "not found")
		return
	}
	n := 24
	var e error
	if kind == "chart" {
		n, e = boundedInt(r.URL.Query().Get("n"), 24, 1, 24)
	}
	if kind == "activity" {
		n, e = boundedInt(r.URL.Query().Get("limit"), 200, 1, 200)
	}
	scope := r.URL.Query().Get("scope")
	if kind == "services" && scope != "" && !contains([]string{"user", "web", "docker", "system", "all"}, scope) {
		e = errors.New("invalid scope")
	}
	if e != nil {
		s.fail(w, 400, e.Error())
		return
	}
	v, e := s.Backend.Collect(r.Context(), kind)
	if e != nil {
		s.result(w, nil, e)
		return
	}
	v = sys.Normalize(v)
	if strings.HasPrefix(p, "runtimes/") {
		id := strings.TrimPrefix(p, "runtimes/")
		if m, ok := v.(map[string]any); ok {
			if rows, ok := m["agents"].([]any); ok {
				for _, a := range rows {
					if m, ok := a.(map[string]any); ok && m["id"] == id {
						s.write(w, 200, m)
						return
					}
				}
			}
		}
		s.fail(w, 404, "unknown runtime")
		return
	}
	if kind == "chart" {
		if rows, ok := v.([]any); ok && len(rows) > n {
			v = rows[len(rows)-n:]
		}
	}
	if m, ok := v.(map[string]any); ok {
		if kind == "activity" {
			if rows, ok := m["events"].([]any); ok && len(rows) > n {
				m["events"] = rows[:n]
			}
		}
		if kind == "services" && scope != "" && scope != "all" {
			rows := []any{}
			rowsIn, ok := m["services"].([]any)
			if !ok {
				m["services"] = rows
				s.write(w, 200, v)
				return
			}
			for _, row := range rowsIn {
				svc, ok := row.(map[string]any)
				if !ok {
					continue
				}
				if scope == "web" {
					if svc["web"] == true {
						rows = append(rows, svc)
					}
				} else if svc["scope"] == scope {
					rows = append(rows, svc)
				}
			}
			m["services"] = rows
		}
	}
	s.write(w, 200, v)
}
func validTmuxActionName(s string) bool {
	return s != "" && !strings.HasPrefix(s, "-") && tmuxActionName.MatchString(s)
}
func boundedInt(s string, def, min, max int) (int, error) {
	if s == "" {
		return def, nil
	}
	n, e := strconv.Atoi(s)
	if e != nil || n < min || n > max {
		return 0, fmt.Errorf("number must be between %d and %d", min, max)
	}
	return n, nil
}
func (s *Server) result(w http.ResponseWriter, v any, e error) {
	if e != nil {
		s.fail(w, 503, "collection unavailable")
		return
	}
	s.write(w, 200, v)
}
func (s *Server) audit(action string, status int) error {
	s.auditMu.Lock()
	defer s.auditMu.Unlock()
	f, e := os.OpenFile(s.Config.AuditLog, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0600)
	if e != nil {
		return e
	}
	defer f.Close()
	if e = f.Chmod(0600); e != nil {
		return e
	}
	return json.NewEncoder(f).Encode(map[string]any{"at": time.Now().UTC().Format(time.RFC3339Nano), "action": redact.Text(action), "status": status})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(n int) { w.status = n; w.ResponseWriter.WriteHeader(n) }
func (s *Server) action(w http.ResponseWriter, r *http.Request, action string) {
	audited := false
	result := &statusWriter{ResponseWriter: w, status: 200}
	w = result
	if r.Method == "POST" {
		defer func() {
			if !audited {
				_ = s.audit(action, result.status)
			}
		}()
	}

	if r.Method != "POST" {
		s.fail(w, 405, "POST required")
		return
	}
	if !s.Config.Writable() {
		s.fail(w, 403, "actions disabled")
		return
	}
	if !auth.Match(s.Config.ActionKey, r.Header.Get("X-Collector-Key")) {
		s.fail(w, 401, "action token required")
		return
	}
	if !contains([]string{"svc-pause", "svc-resume", "unit-start", "unit-stop", "tmux-send", "tmux-kill", "tmux-new", "tmux-wake", "task-run", "quota-refresh"}, action) {
		s.fail(w, 404, "unknown action")
		return
	}
	// No cross-origin browser actions, even with a configured token.
	if r.Header.Get("Origin") != "" {
		s.fail(w, 403, "browser origins are not accepted for actions")
		return
	}
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10))
	d.DisallowUnknownFields()
	var b *Action
	if e := d.Decode(&b); e != nil || b == nil {
		s.fail(w, 400, "invalid JSON body")
		return
	}
	var extra any
	if e := d.Decode(&extra); e != io.EOF {
		s.fail(w, 400, "single JSON object required")
		return
	}
	if e := s.audit(action, 102); e != nil {
		s.fail(w, 503, "audit log unavailable")
		return
	}
	v, e := s.Backend.Action(r.Context(), action, *b)
	status := 200
	if e != nil {
		status = 400
	}
	if err := s.audit(action, status); err != nil {
		s.fail(w, 503, "action attempted; audit completion failed")
		return
	}
	audited = true
	if e != nil {
		s.fail(w, status, "action rejected or failed")
		return
	}
	s.write(w, 200, v)
}
