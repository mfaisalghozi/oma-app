package main

import (
	"context"
	"flag"
	"log"
	"oma/apps/api/internal/describe"
	"oma/apps/api/internal/jobs"
	"oma/apps/api/internal/limits"
	"oma/apps/api/internal/platform/config"
	"oma/apps/api/internal/platform/database"
	"oma/apps/api/internal/platform/storage"
	"oma/apps/api/internal/scores"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	migrate := flag.Bool("migrate", false, "apply River-owned queue migrations and exit")
	flag.Parse()
	signalCtx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	boot, cancel := context.WithTimeout(signalCtx, 10*time.Second)
	defer cancel()
	db, err := database.Open(boot, os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatal("worker database unavailable")
	}
	defer db.Close()
	if *migrate {
		if err = jobs.Migrate(boot, db); err != nil {
			log.Fatal("queue migration failed")
		}
		log.Print("queue migrations applied")
		return
	}
	policy, err := config.LoadDiscovery(os.Getenv("DISCOVERY_POLICY_FILE"))
	if err != nil {
		log.Fatal("invalid discovery configuration")
	}
	projector, err := scores.New(db, policy.Ranking)
	if err != nil {
		log.Fatal("score projection requires valid DISCOVERY_POLICY_FILE")
	}
	benefits, err := limits.NewService(limits.ConfigFromEnvironment(os.Getenv))
	if err != nil {
		log.Fatal("invalid usage configuration")
	}
	var provider describe.JSONProvider
	var store storage.Store = storage.Unavailable{}
	if key := os.Getenv("BEDROCK_API_KEY"); key != "" {
		provider, err = describe.NewBedrock(describe.BedrockConfig{APIKey: key})
		if err != nil {
			log.Fatal("invalid Describe provider configuration")
		}
		configuredStore, e := storage.NewSupabase(os.Getenv("SUPABASE_URL"), os.Getenv("SUPABASE_SERVICE_ROLE_KEY"))
		if e != nil {
			log.Fatal("Describe storage unavailable")
		}
		if e = configuredStore.CheckBucket(boot); e != nil {
			log.Fatal("Describe storage bucket unavailable")
		}
		store = configuredStore
	}
	searches, err := describe.NewService(boot, db, store, policy, benefits, provider)
	if err != nil {
		log.Fatal("invalid Describe configuration")
	}
	runtime, err := jobs.New(db, projector, jobs.Options{RegisterWorkers: searches.RegisterWorkers, Reconcile: searches.Reconcile})
	if err != nil {
		log.Fatal("worker configuration invalid")
	}
	searches.Client = runtime.Client
	// SIGTERM stops intake while in-flight work retains its context during the drain.
	run, cancelRun := context.WithCancel(context.Background())
	defer cancelRun()
	if err = runtime.Start(run); err != nil {
		log.Fatal("worker startup failed; apply queue migrations explicitly first")
	}
	log.Print("Discovery score and Describe worker started")
	<-signalCtx.Done()
	drain, cancelDrain := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancelDrain()
	if err = runtime.Stop(drain); err != nil {
		log.Print("worker drain deadline reached")
	}
	log.Print("worker stopped")
}
