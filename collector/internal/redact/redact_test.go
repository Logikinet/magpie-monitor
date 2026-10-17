package redact

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestPrivacy(t *testing.T) {
	v := map[string]any{"text": "demo-user@example.com /home/demo/work /Users/demo/work sk-fake123456789 Bearer abc.def secret-value token=short", "cwd": "/home/demo/work", "cmdline": "password=short", "key": map[string]any{"set": true, "masked": "sk-***demo", "raw": "private"}, "api_key": "private", "nested": []any{map[string]any{"access_token": "private", "tokens": 120, "input_tokens": 80}}}
	b, _ := json.Marshal(Value(v, false, "secret-value"))
	s := string(b)
	for _, bad := range []string{"demo-user@example.com", "/home/demo", "/Users/demo", "sk-fake123456789", "abc.def", "secret-value", "private", "cwd", "cmdline", "short"} {
		if strings.Contains(s, bad) {
			t.Fatalf("leaked %s: %s", bad, s)
		}
	}
	if !strings.Contains(s, `"tokens":120`) || !strings.Contains(s, "sk-***demo") {
		t.Fatal(s)
	}
	b, _ = json.Marshal(Value(v, true))
	if !strings.Contains(string(b), `"cwd":"~/work"`) {
		t.Fatal(string(b))
	}
}

func TestTerminalSecrets(t *testing.T) {
	for _, s := range []string{"--token short", `password="short"`, "sk-fake\x1b[31m123456789", "demo-user\x1b[0m@example.com", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature"} {
		v := Text(s)
		if v == s || strings.Contains(v, "short") || strings.Contains(v, "signature") {
			t.Fatalf("not sanitized: %q", v)
		}
	}
}
