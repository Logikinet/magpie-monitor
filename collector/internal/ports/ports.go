package ports

import (
	"context"
	"encoding/hex"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"magpie-monitor/collector/internal/command"
)

var pidRE = regexp.MustCompile(`pid=(\d+)`)

func Parse(s string) []map[string]any {
	out := []map[string]any{}
	for _, l := range strings.Split(s, "\n") {
		f := strings.Fields(l)
		if len(f) < 5 || f[0] != "LISTEN" {
			continue
		}
		host, port, e := net.SplitHostPort(f[3])
		if e != nil {
			continue
		}
		n, e := strconv.Atoi(port)
		if e != nil {
			continue
		}
		pids := []int{}
		for _, m := range pidRE.FindAllStringSubmatch(l, -1) {
			p, _ := strconv.Atoi(m[1])
			pids = append(pids, p)
		}
		name := "listener"
		if i := strings.Index(l, `(("`); i >= 0 {
			tail := l[i+3:]
			if j := strings.Index(tail, `"`); j >= 0 {
				name = tail[:j]
			}
		}
		scope := "user"
		if n < 1024 {
			scope = "system"
		}
		out = append(out, map[string]any{"ip": strings.Trim(host, "[]"), "port": n, "pids": pids, "name": name, "type": "direct", "scope": scope, "docker_proxy": strings.Contains(name, "docker-proxy"), "is_self": hasPID(pids, os.Getpid())})
	}
	sort.Slice(out, func(i, j int) bool { return out[i]["port"].(int) < out[j]["port"].(int) })
	return out
}
func Collect(ctx context.Context, run command.Runner) map[string]any {
	s, e := run(ctx, "ss", "-ltnpH")
	services := Parse(s)
	if e != nil {
		services = ProcListeners("/proc")
		if len(services) > 0 {
			e = nil
		}
	}

	out := map[string]any{"updated": time.Now().Unix(), "services": services}
	if e != nil {
		out["unsupported"] = true
	}
	return out
}

// ParseProcNet decodes Linux LISTEN sockets, including their inode for PID lookup.
func ParseProcNet(s string, ipv6 bool) []map[string]any {
	out := []map[string]any{}
	for _, line := range strings.Split(s, "\n") {
		f := strings.Fields(line)
		if len(f) < 10 || f[3] != "0A" {
			continue
		}
		hp := strings.Split(f[1], ":")
		if len(hp) != 2 {
			continue
		}
		raw, e := hex.DecodeString(hp[0])
		if e != nil {
			continue
		}
		if (!ipv6 && len(raw) != 4) || (ipv6 && len(raw) != 16) {
			continue
		}
		for i := 0; i < len(raw); i += 4 {
			raw[i], raw[i+3] = raw[i+3], raw[i]
			raw[i+1], raw[i+2] = raw[i+2], raw[i+1]
		}
		port, e := strconv.ParseInt(hp[1], 16, 32)
		if e != nil {
			continue
		}
		out = append(out, map[string]any{"ip": net.IP(raw).String(), "port": int(port), "inode": f[9], "name": "listener", "pids": []int{}, "scope": "user", "type": "direct", "docker_proxy": false, "is_self": false})
	}
	return out
}
func ProcListeners(root string) []map[string]any {
	out := []map[string]any{}
	for _, file := range []string{"tcp", "tcp6"} {
		b, e := os.ReadFile(filepath.Join(root, "net", file))
		if e == nil {
			out = append(out, ParseProcNet(string(b), file == "tcp6")...)
		}
	}
	byInode := map[string][]map[string]any{}
	for _, svc := range out {
		inode := svc["inode"].(string)
		byInode[inode] = append(byInode[inode], svc)
	}
	dirs, _ := os.ReadDir(root)
	for _, d := range dirs {
		pid, e := strconv.Atoi(d.Name())
		if e != nil {
			continue
		}
		fds, _ := os.ReadDir(filepath.Join(root, d.Name(), "fd"))
		for _, fd := range fds {
			link, _ := os.Readlink(filepath.Join(root, d.Name(), "fd", fd.Name()))
			if !strings.HasPrefix(link, "socket:[") {
				continue
			}
			inode := strings.TrimSuffix(strings.TrimPrefix(link, "socket:["), "]")
			for _, svc := range byInode[inode] {
				pids := svc["pids"].([]int)
				duplicate := false
				for _, p := range pids {
					if p == pid {
						duplicate = true
					}
				}
				if !duplicate {
					svc["pids"] = append(pids, pid)
				}
				comm, _ := os.ReadFile(filepath.Join(root, d.Name(), "comm"))
				if len(comm) > 0 {
					svc["name"] = strings.TrimSpace(string(comm))
				}
				cgroup, _ := os.ReadFile(filepath.Join(root, d.Name(), "cgroup"))
				if strings.Contains(string(cgroup), "/system.slice/") {
					svc["scope"] = "system"
				}
				for _, part := range strings.Split(string(cgroup), "/") {
					if strings.HasSuffix(strings.TrimSpace(part), ".service") {
						svc["unit"] = strings.TrimSpace(part)
						svc["type"] = "systemd"
					}
				}
			}
		}
	}
	for _, svc := range out {
		delete(svc, "inode")
		svc["is_self"] = false
		for _, pid := range svc["pids"].([]int) {
			if pid == os.Getpid() {
				svc["is_self"] = true
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return fmt.Sprint(out[i]["port"]) < fmt.Sprint(out[j]["port"]) })
	return out
}

func hasPID(pids []int, pid int) bool {
	for _, p := range pids {
		if p == pid {
			return true
		}
	}
	return false
}
