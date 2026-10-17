package docker

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
	v := Parse(fixture(t, "ps.jsonl"))
	if len(v) != 1 || v[0]["container_id"] != "fake123" {
		t.Fatalf("%#v", v)
	}
}
