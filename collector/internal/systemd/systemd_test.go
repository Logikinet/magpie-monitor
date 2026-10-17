package systemd

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
	v := Parse(fixture(t, "units.txt"))
	if len(v) != 1 || v[0]["unit"] != "devbox.service" {
		t.Fatalf("%#v", v)
	}
}
