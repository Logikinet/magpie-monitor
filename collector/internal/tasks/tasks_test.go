package tasks

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
	v := ParseTimers(fixture(t, "timers.json"), "user")
	c := ParseCron(fixture(t, "crontab.txt"))
	if len(v) != 1 || len(c) != 2 || v[0]["scope"] != "user" {
		t.Fatalf("%#v %#v", v, c)
	}
}
