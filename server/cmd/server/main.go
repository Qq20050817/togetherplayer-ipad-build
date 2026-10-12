package main

import (
	"context"
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	"together/poc/internal/backend"
)

func main() {
	addr := flag.String("listen", "127.0.0.1:8080", "HTTP bind address; put TLS reverse proxy in front")
	db := flag.String("db", "together.db", "SQLite file")
	metrics := flag.String("metrics", "telemetry.jsonl", "device telemetry")
	flag.Parse()
	f, e := os.OpenFile(*metrics, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if e != nil {
		log.Fatal(e)
	}
	defer f.Close()
	s, e := backend.New(*db, json.NewEncoder(f))
	if e != nil {
		log.Fatal(e)
	}
	defer s.Close()
	h := &http.Server{Addr: *addr, Handler: s.Handler(), ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 60 * time.Second}
	go func() {
		log.Printf("listening %s", *addr)
		if e := h.ListenAndServe(); e != http.ErrServerClosed {
			log.Fatal(e)
		}
	}()
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
	<-ch
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	h.Shutdown(ctx)
}
