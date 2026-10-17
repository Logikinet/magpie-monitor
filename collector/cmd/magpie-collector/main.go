package main

import (
	"context"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"magpie-monitor/collector/internal/api"
	"magpie-monitor/collector/internal/config"
)

func main() {
	path := flag.String("config", "", "optional JSON configuration")
	remote := flag.Bool("allow-remote", false, "allow a non-loopback listener with a read key")
	flag.Parse()
	c, e := config.Load(*path)
	if e != nil {
		log.Fatal("invalid configuration: ", e)
	}
	if e = c.ValidateBind(*remote); e != nil {
		log.Fatal(e)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	local := api.New(c)
	local.Start(ctx)
	srv := &http.Server{Addr: c.Addr, Handler: &api.Server{Config: c, Backend: local, Proxy: local.Magpie}, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 2 * time.Minute, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 16 << 10}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdown)
	}()
	log.Printf("magpie-collector %s listening on %s (readonly=%v)", api.Version, c.Addr, !c.Writable())
	if e = srv.ListenAndServe(); e != nil && e != http.ErrServerClosed {
		log.Fatal(e)
	}
}
