package magpie

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestAggregation(t *testing.T) {
	seen := map[string]int{}
	up := newUpstream(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen[r.URL.Path]++
		if r.URL.Query().Has("asked") {
			t.Error("asked forwarded")
		}
		if r.URL.Query().Has("k") {
			t.Error("key query")
		}
		if !strings.Contains(r.Header.Get("Cookie"), "demo-upstream") {
			t.Error("missing cookie")
		}
		switch r.URL.Path {
		case "/api/gateway/trace":
			_, _ = w.Write([]byte(`{"seq":2,"routes":[{"seq":1},{"seq":2}],"totals":{"requests":2}}`))
		case "/api/gateway/history":
			_, _ = w.Write([]byte(`{"days":[]}`))
		case "/api/groups":
			_, _ = w.Write([]byte(`{"groups":[],"pools":[]}`))
		case "/api/usage":
			if r.URL.Query().Get("period") != "today" {
				t.Error("period")
			}
			_, _ = w.Write([]byte(`{"calls":2,"input":10,"output":20}`))
		case "/api/usage/quotas":
			_, _ = w.Write([]byte(`[]`))
		case "/api/providers":
			_, _ = w.Write([]byte(`{"providers":[{"id":"demo","key":{"masked":"sk-***demo","raw":"private"},"api_key":"private","account":{"user":"demo-user@example.com"}}]}`))
		default:
			t.Error(r.URL.Path)
		}
	}))
	defer up.Close()
	c := &Client{Base: up.URL, Key: "demo-upstream", HTTP: up.Client}
	for _, kind := range []string{"routing", "usage", "providers"} {
		v, e := c.Get(context.Background(), kind, "bad&asked=1")
		if e != nil || v["fetched_at"] == nil {
			t.Fatalf("%v %v", v, e)
		}
		b, _ := json.Marshal(v)
		if strings.Contains(string(b), "private") || strings.Contains(string(b), "demo-user@example.com") {
			t.Fatal(string(b))
		}
		if _, e = c.Get(context.Background(), kind, "bad&asked=1"); e != nil {
			t.Fatal(e)
		}
	}
	if seen["/api/usage/quotas"] != 1 || seen["/api/gateway/trace"] != 1 {
		t.Fatal(seen)
	}
	old := c.cache["routing:today"]
	old.at = time.Time{}
	c.cache["routing:today"] = old
	up.Close()
	v, e := c.Get(context.Background(), "routing", "today")
	if e != nil || v["stale"] != true || v["fetched_at"] != old.value["fetched_at"] {
		t.Fatalf("%v %v", v, e)
	}
}
func TestNoRedirectCredentials(t *testing.T) {
	target := newUpstream(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { t.Error("redirect followed") }))
	defer target.Close()
	up := newUpstream(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, target.URL, 302) }))
	defer up.Close()
	c := Client{Base: up.URL, Key: "demo-upstream", HTTP: up.Client}
	if _, e := c.Get(context.Background(), "providers", ""); e == nil {
		t.Fatal("redirect accepted")
	}
}

// httptest recorder upstream avoids opening sockets in restricted sandboxes.
type upstream struct {
	URL    string
	Client *http.Client
	closed bool
}
type handlerTransport struct {
	handler http.Handler
	up      *upstream
}

func (t handlerTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	if t.up.closed {
		return nil, errors.New("closed")
	}
	w := httptest.NewRecorder()
	t.handler.ServeHTTP(w, r)
	return w.Result(), nil
}
func newUpstream(handler http.Handler) *upstream {
	u := &upstream{URL: "http://example.invalid:3426"}
	u.Client = &http.Client{Transport: handlerTransport{handler, u}}
	return u
}
func (u *upstream) Close() { u.closed = true }
