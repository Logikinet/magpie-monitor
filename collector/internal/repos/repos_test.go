package repos

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
	v := ParseLog(fixture(t, "log.txt"), "devbox", "main")
	if len(v) != 1 || v[0]["subject"] != "Add example dashboard" || v[0]["origin"] != "local" {
		t.Fatalf("%#v", v)
	}
}
