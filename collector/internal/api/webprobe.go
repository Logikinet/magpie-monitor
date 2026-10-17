package api

import (
	"context"
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"
)

type webResult struct {
	web bool
	at  time.Time
}

var webResults = struct {
	sync.Mutex
	byPort map[int]webResult
}{byPort: map[int]webResult{}}

func markWebServices(services []map[string]any) {
	probed := 0
	seen := map[int]bool{}
	results := map[int]bool{}
	for _, service := range services {
		port, ok := service["port"].(int)
		web := false
		if ok && port > 0 && port <= 65535 && port != 22 && port != 5355 && port != 22000 {
			if seen[port] {
				web = results[port]
			} else {
				seen[port] = true
				web, _ = lookupWeb(port, &probed)
				results[port] = web
			}
		}
		service["web"] = web
	}
}

func lookupWeb(port int, probed *int) (bool, bool) {
	now := time.Now()
	webResults.Lock()
	if result, ok := webResults.byPort[port]; ok && now.Sub(result.at) < time.Minute {
		webResults.Unlock()
		return result.web, true
	}
	if *probed >= 32 {
		webResults.Unlock()
		return false, false
	}
	(*probed)++
	webResults.Unlock()

	client := &http.Client{Timeout: 300 * time.Millisecond, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	isWeb := probeWeb(client, port)
	webResults.Lock()
	webResults.byPort[port] = webResult{web: isWeb, at: now}
	webResults.Unlock()
	return isWeb, false
}

func probeWeb(client *http.Client, port int) bool {
	url := "http://" + net.JoinHostPort("127.0.0.1", strconv.Itoa(port)) + "/"
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	request, _ := http.NewRequestWithContext(ctx, http.MethodHead, url, nil)
	response, err := client.Do(request)
	if err != nil {
		request, _ = http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		response, err = client.Do(request)
	}
	isWeb := err == nil
	if response != nil {
		_ = response.Body.Close()
	}
	return isWeb
}
