package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"magpie-monitor/collector/internal/config"
)

type fake struct{ calls int }

func (f *fake) Collect(_ context.Context, kind string) (any, error) {
	switch kind {
	case "runtimes":
		return map[string]any{"agents": []any{map[string]any{"id": "codex", "installed": true}}}, nil
	case "services":
		return map[string]any{"services": []any{map[string]any{"scope": "user", "port": 8080, "web": true, "cmdline": "hidden", "cwd": "/home/demo/devbox", "text": "demo-user@example.com"}, map[string]any{"scope": "system", "port": 22, "web": false}, "malformed", map[string]any{"port": 1234}}}, nil
	case "chart":
		return []any{1, 2, 3}, nil
	case "activity":
		return map[string]any{"events": []any{1, 2, 3}}, nil
	}
	return map[string]any{}, nil
}
func (f *fake) Action(context.Context, string, Action) (any, error) {
	f.calls++
	return map[string]any{"ok": true}, nil
}
func (f *fake) Capture(_ context.Context, _ string, n int, _ bool) (any, error) {
	return map[string]any{"text": "safe", "lines_requested": n}, nil
}
func request(s *Server, method, path, key, body string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, Prefix+path, strings.NewReader(body))
	r.Header.Set("X-Collector-Key", key)
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	return w
}
func TestHandlers(t *testing.T) {
	f := &fake{}
	s := &Server{Backend: f, Config: config.Config{Key: "demo-read", AuditLog: filepath.Join(t.TempDir(), "audit.jsonl")}}
	for _, key := range []string{"", "wrong"} {
		if w := request(s, "GET", "sys", key, ""); w.Code != 401 {
			t.Fatal(w.Code)
		}
	}
	for _, p := range append(append([]string{}, parts...), "hello", "snapshot", "runtimes/codex", "tmux/capture?target=%251&lines=30", "services?scope=web", "chart?n=2", "activity?limit=1") {
		w := request(s, "GET", p, "demo-read", "")
		if w.Code != 200 {
			t.Fatalf("%s: %d %s", p, w.Code, w.Body)
		}
		if strings.Contains(w.Body.String(), "demo-user@example.com") || strings.Contains(w.Body.String(), "cmdline") {
			t.Fatal(w.Body)
		}
	}
	for _, p := range []string{"chart?n=25", "activity?limit=no", "services?scope=bogus", "tmux/capture?target=-a", "tmux/capture?target=demo&lines=0"} {
		if w := request(s, "GET", p, "demo-read", ""); w.Code != 400 {
			t.Fatalf("%s %d", p, w.Code)
		}
	}
	if request(s, "GET", "runtimes/missing", "demo-read", "").Code != 404 {
		t.Fatal("runtime 404")
	}
	if request(s, "POST", "sys", "demo-read", "").Code != 405 {
		t.Fatal("method")
	}
	w := request(s, "GET", "hello", "demo-read", "")
	var h map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &h)
	if h["readonly"] != true {
		t.Fatal(h)
	}
}
func TestHelloAdvertisesWritableActions(t *testing.T) {
	s := &Server{Backend: &fake{}, Config: config.Config{AllowActions: true, ActionKey: "demo-action", AuditLog: filepath.Join(t.TempDir(), "audit.jsonl")}}
	w := request(s, "GET", "hello", "", "")
	var hello map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &hello); err != nil {
		t.Fatal(err)
	}
	caps := hello["caps"].([]any)
	for _, expected := range []string{"actions/tmux-send", "actions/tmux-kill", "actions/tmux-new", "actions/tmux-wake", "actions/quota-refresh"} {
		found := false
		for _, cap := range caps {
			if cap == expected {
				found = true
			}
		}
		if !found {
			t.Fatalf("missing %s from %#v", expected, caps)
		}
	}
}
func TestWebScopeSkipsMalformedRowsAndUsesWebFlag(t *testing.T) {
	f := &fake{}
	s := &Server{Backend: f}
	w := request(s, "GET", "services?scope=web", "", "")
	if w.Code != 200 || strings.Count(w.Body.String(), `"port"`) != 1 || !strings.Contains(w.Body.String(), `"web":true`) {
		t.Fatalf("unexpected web-filter response: %d %s", w.Code, w.Body)
	}
}
func TestActions(t *testing.T) {
	f := &fake{}
	audit := filepath.Join(t.TempDir(), "audit.jsonl")
	s := &Server{Backend: f, Config: config.Config{AuditLog: audit}}
	for _, c := range []config.Config{{AuditLog: audit}, {AllowActions: true, AuditLog: audit}, {ActionKey: "demo-action", AuditLog: audit}} {
		s.Config = c
		if request(s, "POST", "actions/unit-start", "demo-action", `{"unit":"devbox.service"}`).Code != 403 {
			t.Fatal("actions enabled")
		}
	}
	s.Config = config.Config{Key: "demo-read", ActionKey: "demo-action", AllowActions: true, AuditLog: audit}
	for _, key := range []string{"", "wrong", "demo-read"} {
		if request(s, "POST", "actions/unit-start", key, `{}`).Code != 401 {
			t.Fatal("unauthorized")
		}
	}
	for _, body := range []string{`{"unknown":1}`, `{} {}`, `null`, `[]`} {
		if request(s, "POST", "actions/unit-start", "demo-action", body).Code != 400 {
			t.Fatalf("accepted %s", body)
		}
	}
	if request(s, "POST", "actions/unit-start", "demo-action", `{"unit":"devbox.service"}`).Code != 200 || f.calls != 1 {
		t.Fatal("action failed", f.calls)
	}
	b, e := os.ReadFile(audit)
	if e != nil || !strings.Contains(string(b), `"status":200`) || strings.Contains(string(b), "demo-action") {
		t.Fatalf("%s %v", b, e)
	}
	s.Config.AuditLog = filepath.Join(t.TempDir(), "missing", "audit")
	if request(s, "POST", "actions/unit-start", "demo-action", `{}`).Code != 503 || f.calls != 1 {
		t.Fatal("audit must fail closed")
	}
}
func TestActionAllowlist(t *testing.T) {
	l := New(config.Config{Units: []string{"user:devbox.service"}})
	calls := []string{}
	l.Run = func(_ context.Context, name string, args ...string) (string, error) {
		calls = append(calls, name+" "+strings.Join(args, " "))
		return "", nil
	}
	if _, e := l.Action(context.Background(), "unit-start", Action{Unit: "other.service"}); e == nil {
		t.Fatal("allowlist bypass")
	}
	if _, e := l.Action(context.Background(), "unit-start", Action{Unit: "devbox.service", Scope: "system"}); e == nil {
		t.Fatal("scope bypass")
	}
	for _, a := range []string{"unit-start", "unit-stop", "svc-pause", "svc-resume", "task-run"} {
		_, e := l.Action(context.Background(), a, Action{Unit: "devbox.service", Name: "devbox.timer"})
		if e != nil {
			t.Fatal(e)
		}
	}
	for _, item := range []struct {
		action   string
		body     Action
		expected string
	}{
		{"tmux-kill", Action{Session: "demo.session"}, "tmux kill-session -t =demo.session"},
		{"tmux-new", Action{Name: "demo-session"}, "tmux new-session -d -s demo-session"},
		{"tmux-wake", Action{Session: "demo"}, "tmux new-session -Ad -s demo"},
	} {
		if _, e := l.Action(context.Background(), item.action, item.body); e != nil || calls[len(calls)-1] != item.expected {
			t.Fatalf("%s: calls=%v err=%v", item.action, calls, e)
		}
	}
	for _, session := range []string{"-a", "bad name", ""} {
		if _, e := l.Action(context.Background(), "tmux-wake", Action{Session: session}); e == nil {
			t.Fatalf("accepted invalid session %q", session)
		}
	}
	if _, e := l.Action(context.Background(), "tmux-send", Action{Target: "-a"}); e == nil {
		t.Fatal("option injection")
	}
	_, e := l.Action(context.Background(), "tmux-send", Action{Target: "%1", Text: "$(id); --bad", Enter: true})
	if e != nil {
		t.Fatal(e)
	}
	if !strings.Contains(fmt.Sprint(calls), "-l -- $(id); --bad") {
		t.Fatal(calls)
	}
}
func TestWebProbe(t *testing.T) {
	called := false
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		called = true
		recorder := httptest.NewRecorder()
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNotFound) }).ServeHTTP(recorder, r)
		response := recorder.Result()
		response.Request = r
		return response, nil
	})}
	if !probeWeb(client, 49152) || !called {
		t.Fatal("an HTTP response should identify a web listener")
	}
	services := []map[string]any{{"port": 22}, {"port": 5355}, {"port": "bad"}}
	markWebServices(services)
	if services[0]["web"] != false || services[1]["web"] != false || services[2]["web"] != false {
		t.Fatalf("probe results: %#v", services)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestLocalCachesAndRing(t *testing.T) {
	l := New(config.Config{})
	calls := 0
	l.Run = func(context.Context, string, ...string) (string, error) { calls++; return "", nil }
	for i := 0; i < 30; i++ {
		l.Sample(context.Background())
	}
	v, e := l.Collect(context.Background(), "chart")
	if e != nil || len(v.([]map[string]any)) != 24 {
		t.Fatalf("ring: %v %v", v, e)
	}
	_, _ = l.Collect(context.Background(), "tasks")
	before := calls
	_, _ = l.Collect(context.Background(), "tasks")
	if calls != before {
		t.Fatal("cache miss")
	}
	_, _ = l.Collect(context.Background(), "unknown")
	if calls != before {
		t.Fatal("unknown command")
	}
}

func TestQuotaRefreshInvalidatesRuntimeCache(t *testing.T) {
	l := New(config.Config{})
	l.cache["runtimes"] = cached{value: map[string]any{"stale": true}, at: time.Now()}
	if _, err := l.Action(context.Background(), "quota-refresh", Action{}); err != nil {
		t.Fatal(err)
	}
	if _, exists := l.cache["runtimes"]; exists {
		t.Fatal("runtime cache was not invalidated")
	}
}
