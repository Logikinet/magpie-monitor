package ports

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
	v := Parse(fixture(t, "ss.txt"))
	if len(v) != 2 || v[1]["port"] != 8080 || v[1]["name"] != "devbox" {
		t.Fatalf("%#v", v)
	}
	p := ParseProcNet(fixture(t, "tcp.txt"), false)
	if len(p) != 1 || p[0]["ip"] != "127.0.0.1" || p[0]["port"] != 8080 || p[0]["inode"] != "4242" {
		t.Fatalf("%#v", p)
	}
	if len(Parse("garbage")) != 0 {
		t.Fatal("bad input accepted")
	}
}
