package tailscale

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
	v, e := Parse(fixture(t, "status.json"))
	if e != nil || v["backend_state"] != "Running" {
		t.Fatalf("%v %v", v, e)
	}
	if _, ok := v["PrivateKey"]; ok {
		t.Fatal("unexpected key")
	}
	if _, ok := v["User"]; ok {
		t.Fatal("user leaked")
	}
	if _, e := Parse("garbage"); e == nil {
		t.Fatal("bad input")
	}
}
