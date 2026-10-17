package config

import (
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Addr          string   `json:"addr"`
	Key           string   `json:"key"`
	ActionKey     string   `json:"action_key"`
	AllowActions  bool     `json:"allow_actions"`
	WebURL        string   `json:"magpie_web_url"`
	WebKey        string   `json:"magpie_web_key"`
	Repos         []string `json:"repos"`
	ExposeCmdline bool     `json:"expose_cmdline"`
	Units         []string `json:"units"`
	AuditLog      string   `json:"audit_log"`
}

func Load(path string) (Config, error) {
	c := Config{Addr: "127.0.0.1:8787", AuditLog: "collector-audit.jsonl"}
	if path != "" {
		f, e := os.Open(path)
		if e != nil {
			return c, e
		}
		defer f.Close()
		d := json.NewDecoder(f)
		d.DisallowUnknownFields()
		if e = d.Decode(&c); e != nil {
			return c, e
		}
		var extra any
		if e = d.Decode(&extra); e != io.EOF {
			return c, errors.New("config must contain one JSON object")
		}
	}
	for k, p := range map[string]*string{"MAGPIE_COLLECTOR_ADDR": &c.Addr, "MAGPIE_COLLECTOR_KEY": &c.Key, "MAGPIE_COLLECTOR_ACTION_KEY": &c.ActionKey, "MAGPIE_WEB_URL": &c.WebURL, "MAGPIE_WEB_KEY": &c.WebKey} {
		if v, ok := os.LookupEnv(k); ok {
			*p = v
		}
	}
	for k, p := range map[string]*bool{"MAGPIE_COLLECTOR_ALLOW_ACTIONS": &c.AllowActions, "MAGPIE_COLLECTOR_EXPOSE_CMDLINE": &c.ExposeCmdline} {
		if v, ok := os.LookupEnv(k); ok {
			b, e := strconv.ParseBool(v)
			if e != nil {
				return c, e
			}
			*p = b
		}
	}
	if v, ok := os.LookupEnv("MAGPIE_COLLECTOR_REPOS"); ok {
		c.Repos = nil
		for _, r := range strings.Split(v, string(os.PathListSeparator)) {
			if r != "" {
				c.Repos = append(c.Repos, r)
			}
		}
	}
	if c.WebURL != "" {
		u, e := url.Parse(c.WebURL)
		if e != nil || u.Host == "" || u.User != nil || (u.Scheme != "http" && u.Scheme != "https") || u.RawQuery != "" || u.Fragment != "" {
			return c, errors.New("invalid magpie_web_url")
		}
	}
	return c, nil
}
func (c Config) ValidateBind(remote bool) error {
	host, _, e := net.SplitHostPort(c.Addr)
	if e != nil {
		return e
	}
	ip := net.ParseIP(host)
	if ip == nil || !ip.IsLoopback() {
		if !remote || c.Key == "" {
			return errors.New("non-loopback bind requires -allow-remote and a read key")
		}
	}
	return nil
}
func (c Config) Writable() bool { return c.AllowActions && c.ActionKey != "" }
