package redact

import (
	"regexp"
	"strings"
)

var patterns = []*regexp.Regexp{
	regexp.MustCompile(`eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`),
	regexp.MustCompile(`(?is)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----`),
	regexp.MustCompile(`(?i)--(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret|token)\s+(?:"[^"\n]*"|'[^'\n]*'|[^\s;]+)`),
	regexp.MustCompile(`(?i)(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret|token)\s*[=:]\s*(?:"[^"\n]*"|'[^'\n]*')`),
	regexp.MustCompile(`https?://[^/\s@]+:[^/\s@]+@`),
	regexp.MustCompile(`[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}`),
	regexp.MustCompile(`(?i)(bearer\s+)[A-Za-z0-9._~+/=\-]+`),
	regexp.MustCompile(`(?i)(?:sk-|ghp_|github_pat_|gho_|AIza|AKIA)[A-Za-z0-9_\-]{8,}`),
	regexp.MustCompile(`[A-Za-z0-9_\-]{32,}(?:\.[A-Za-z0-9_\-]+){0,2}`),
	regexp.MustCompile(`(?i)(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret|token)\s*[=:]\s*[^\s,;"']+`),
}
var home = regexp.MustCompile(`(?:/home/|/Users/)[^/\s"']+|/root\b`)

var ansi = regexp.MustCompile("\x1b\\[[0-?]*[ -/]*[@-~]")

func Text(s string, secrets ...string) string {
	plain := ansi.ReplaceAllString(s, "")
	cleaned := text(plain, secrets...)
	if plain != s && cleaned != plain {
		return cleaned
	}
	return text(s, secrets...)
}
func text(s string, secrets ...string) string {
	for _, v := range secrets {
		if v != "" {
			s = strings.ReplaceAll(s, v, "[redacted]")
		}
	}
	s = home.ReplaceAllString(s, "~")
	for _, p := range patterns {
		s = p.ReplaceAllString(s, "[redacted]")
	}
	return s
}
func secretField(k string) bool {
	k = strings.ToLower(strings.ReplaceAll(k, "_", ""))
	return strings.Contains(k, "key") || strings.Contains(k, "token") || strings.Contains(k, "secret") || strings.Contains(k, "password") || k == "authorization" || k == "authheader" || k == "cookie" || k == "proxy" || k == "auth" || k == "credentials" || k == "authentication"
}

// Value sanitizes decoded JSON. Key containers retain only an explicit masked value.
func Value(v any, expose bool, secrets ...string) any {
	switch x := v.(type) {
	case map[string]any:
		out := map[string]any{}
		for k, v := range x {
			l := strings.ToLower(k)
			if !expose && (l == "cmdline" || l == "cwd" || l == "main_cwd" || l == "cmd") {
				continue
			}
			if l == "masked" {
				if s, ok := v.(string); ok && (strings.ContainsAny(s, "*•…") || strings.Contains(s, "...")) {
					out[k] = Text(s, secrets...)
				}
				continue
			}
			numericUsage := false
			switch strings.ReplaceAll(l, "_", "") {
			case "tokens", "inputtokens", "outputtokens", "totaltokens", "cachereadtokens", "cachewritetokens", "reasoningtokens", "prompttokens", "completiontokens":
				switch v.(type) {
				case float64, int, int64:
					numericUsage = true
				}
			}
			if secretField(k) && !numericUsage && l != "has_key" && l != "key_present" {
				if m := masked(v, secrets...); m != nil {
					out[k] = m
				}
				continue
			}
			out[k] = Value(v, expose, secrets...)
		}
		return out
	case []any:
		out := make([]any, 0, len(x))
		for _, v := range x {
			out = append(out, Value(v, expose, secrets...))
		}
		return out
	case string:
		return Text(x, secrets...)
	default:
		return v
	}
}

func masked(v any, secrets ...string) any {
	switch x := v.(type) {
	case map[string]any:
		if s, ok := x["masked"].(string); ok && (strings.ContainsAny(s, "*•…") || strings.Contains(s, "...")) {
			return map[string]any{"masked": Text(s, secrets...)}
		}
	case []any:
		out := []any{}
		for _, item := range x {
			if m := masked(item, secrets...); m != nil {
				out = append(out, m)
			}
		}
		if len(out) > 0 {
			return out
		}
	}
	return nil
}
