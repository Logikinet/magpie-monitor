package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestBind(t *testing.T) {
	for _, v := range []struct {
		addr, key  string
		remote, ok bool
	}{{"127.0.0.1:8787", "", false, true}, {"[::1]:8787", "", false, true}, {"0.0.0.0:8787", "", true, false}, {"0.0.0.0:8787", "demo", false, false}, {"0.0.0.0:8787", "demo", true, true}, {"localhost:8787", "", false, false}} {
		c := Config{Addr: v.addr, Key: v.key}
		if (c.ValidateBind(v.remote) == nil) != v.ok {
			t.Fatal(v)
		}
	}
}
func TestConfig(t *testing.T) {
	p := filepath.Join(t.TempDir(), "config.json")
	_ = os.WriteFile(p, []byte(`{"addr":"127.0.0.1:9000","allow_actions":true,"units":["user:devbox.service"]}`), 0600)
	t.Setenv("MAGPIE_COLLECTOR_ADDR", "127.0.0.1:9001")
	c, e := Load(p)
	if e != nil || c.Addr != "127.0.0.1:9001" || c.Writable() {
		t.Fatalf("%+v %v", c, e)
	}
	t.Setenv("MAGPIE_COLLECTOR_ALLOW_ACTIONS", "invalid")
	if _, e := Load(p); e == nil {
		t.Fatal("invalid bool")
	}
}
