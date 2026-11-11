// Command auth-check reports public Supabase Auth configuration flags without writes.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"oma/apps/api/internal/platform/authcheck"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	report, err := authcheck.Check(ctx, os.Getenv("SUPABASE_URL"), os.Getenv("SUPABASE_PUBLISHABLE_KEY"))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	if err = encoder.Encode(report); err != nil {
		fmt.Fprintln(os.Stderr, "cannot write Auth check report")
		os.Exit(1)
	}
	if !report.PublicSettingsMatch {
		os.Exit(2)
	}
}
