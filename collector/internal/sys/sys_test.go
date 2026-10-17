package sys

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
	m := ParseMem(fixture(t, "meminfo.txt"))
	if m["total"] != float64(1024000) || m["percent"] != float64(60) || m["swap_percent"] != float64(25) {
		t.Fatalf("%#v", m)
	}
	total, idle := ParseCPU(fixture(t, "stat.txt"))
	if total != 1000 || idle != 850 {
		t.Fatalf("%d %d", total, idle)
	}
	l := ParseLoad("{ 1.0 2.0 3.0 }")
	if len(l) != 3 || l[2] != 3 {
		t.Fatal(l)
	}
}
