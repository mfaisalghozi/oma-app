package main

import (
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	addr := os.Getenv("API_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	server := &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	log.Printf("API listening on %s", addr)
	log.Fatal(server.ListenAndServe())
}
