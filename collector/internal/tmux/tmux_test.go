package tmux

import (
	"os"
	"testing"
)

func fixture(t *testing.T, name string) string {
	t.Helper()
	b, e := os.ReadFile("testdata/" + name)
	if e != nil {
		t.Fatal(e)
	}
	return string(b)
}
func TestParsers(t *testing.T) {
	v := ParseSessions(fixture(t, "sessions.txt"))
	p := ParsePanes(fixture(t, "panes.txt"))
	if len(v) != 1 || v[0]["attached"] != true || len(p) != 1 || p[0]["target"] != "%1" {
		t.Fatalf("%#v %#v", v, p)
	}
	for _, s := range []string{"-a", "x;id", "$(id)", "", "x\n"} {
		if ValidTarget(s) {
			t.Fatalf("accepted %q", s)
		}
	}
	if !ValidTarget("devbox:0.1") || !ValidTarget("%1") {
		t.Fatal("valid target rejected")
	}
}
