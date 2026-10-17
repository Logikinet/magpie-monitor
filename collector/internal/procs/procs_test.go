package procs

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
	v := Parse(fixture(t, "ps.txt"))
	if len(v) != 1 || v[0].PID != 123 || v[0].Mem != 2 || v[0].Name != "codex" {
		t.Fatal(v)
	}
}
