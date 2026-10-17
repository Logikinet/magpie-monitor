package auth

import "testing"

func TestMatch(t *testing.T) {
	for _, v := range []struct {
		want, got string
		ok        bool
	}{{"", "", false}, {"demo-read-key", "", false}, {"demo-read-key", "wrong", false}, {"demo-read-key", "demo-read-key", true}} {
		if Match(v.want, v.got) != v.ok {
			t.Fatal(v)
		}
	}
}
