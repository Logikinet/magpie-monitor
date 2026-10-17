// Package magpie aggregates only fixed read-only Web GUI paths.
package magpie

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"magpie-monitor/collector/internal/redact"
)

type entry struct {
	value map[string]any
	at    time.Time
}
type Client struct {
	Base, Key string
	HTTP      *http.Client
	mu        sync.Mutex
	cache     map[string]entry
}

func (c *Client) fetch(ctx context.Context, path string) (map[string]any, any, error) {
	u, e := url.Parse(c.Base)
	if e != nil || u.Host == "" {
		return nil, nil, errors.New("magpie is not configured")
	}
	ref, _ := url.Parse(path)
	u = u.ResolveReference(ref)
	req, e := http.NewRequestWithContext(ctx, "GET", u.String(), nil)
	if e != nil {
		return nil, nil, e
	}
	if c.Key != "" {
		port := u.Port()
		if port == "" {
			port = "80"
			if u.Scheme == "https" {
				port = "443"
			}
		}
		req.AddCookie(&http.Cookie{Name: "magpie_web_" + port, Value: c.Key})
	}
	client := c.HTTP
	if client == nil {
		client = &http.Client{Timeout: 4 * time.Second}
	}
	copyClient := *client
	copyClient.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	resp, e := copyClient.Do(req)
	if e != nil {
		return nil, nil, errors.New("magpie request failed")
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, nil, errors.New("magpie returned an error")
	}
	b, e := io.ReadAll(io.LimitReader(resp.Body, 4<<20+1))
	if e != nil || len(b) > 4<<20 {
		return nil, nil, errors.New("magpie response too large")
	}
	var v any
	if e = json.Unmarshal(b, &v); e != nil {
		return nil, nil, errors.New("invalid magpie JSON")
	}
	m, _ := v.(map[string]any)
	return m, v, nil
}
func (c *Client) Get(ctx context.Context, kind, period string) (map[string]any, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cache == nil {
		c.cache = map[string]entry{}
	}
	ttl := 8 * time.Second
	if kind == "providers" {
		ttl = 30 * time.Second
	}
	if kind == "usage" {
		ttl = 15 * time.Second
		if period == "7d" {
			ttl = time.Minute
		}
		if period == "30d" || period == "all" {
			ttl = 2 * time.Minute
		}
	}
	if period != "today" && period != "7d" && period != "30d" && period != "all" {
		period = "today"
	}
	key := kind + ":" + period
	old, exists := c.cache[key]
	if exists && time.Since(old.at) < ttl {
		return clone(old.value), nil
	}
	out := map[string]any{}
	var err error
	switch kind {
	case "routing":
		out, _, err = c.fetch(ctx, "/api/gateway/trace?after=0")
		if err == nil {
			for _, part := range []struct {
				path   string
				fields []string
			}{{"/api/gateway/history", []string{"days"}}, {"/api/groups", []string{"groups", "pools"}}} {
				m, _, e := c.fetch(ctx, part.path)
				for _, f := range part.fields {
					if e == nil && m != nil {
						out[f] = m[f]
					} else if exists {
						out[f] = old.value[f]
						out["partial"] = true
					} else {
						out[f] = []any{}
						out["partial"] = true
					}
				}
			}
		}
	case "usage":
		out, _, err = c.fetch(ctx, "/api/usage?period="+url.QueryEscape(period))
		if err == nil {
			_, v, e := c.fetch(ctx, "/api/usage/quotas")
			if e == nil {
				if m, ok := v.(map[string]any); ok {
					out["quotas"] = m["quotas"]
				} else {
					out["quotas"] = v
				}
			} else {
				out["quotas"] = []any{}
				out["partial"] = true
			}
		}
	case "providers":
		out, _, err = c.fetch(ctx, "/api/providers")
	default:
		return nil, errors.New("unknown aggregation")
	}
	if err != nil || out == nil {
		if exists {
			out = clone(old.value)
			out["stale"] = true
			return out, nil
		}
		return nil, errors.New("magpie data unavailable")
	}
	out = redact.Value(out, true, c.Key).(map[string]any)
	out["ok"] = true
	out["fetched_at"] = float64(time.Now().UnixMilli()) / 1000
	c.cache[key] = entry{clone(out), time.Now()}
	return out, nil
}
func clone(m map[string]any) map[string]any {
	b, _ := json.Marshal(m)
	var out map[string]any
	_ = json.NewDecoder(strings.NewReader(string(b))).Decode(&out)
	return out
}
