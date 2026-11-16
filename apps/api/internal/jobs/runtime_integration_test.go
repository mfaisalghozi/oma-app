//go:build integration

package jobs_test

import (
	"context"
	"database/sql"
	"fmt"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/riverqueue/river"
	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/jobs"
	"oma/apps/api/internal/scores"
	"oma/apps/api/migrations"
	"os"
	"testing"
	"time"
)

type controlledArgs struct{}

func (controlledArgs) Kind() string { return "controlled_test" }

type controlledWorker struct {
	river.WorkerDefaults[controlledArgs]
	entered   chan struct{}
	release   chan struct{}
	cancelled chan struct{}
}

func (w *controlledWorker) Work(ctx context.Context, _ *river.Job[controlledArgs]) error {
	close(w.entered)
	select {
	case <-w.release:
		return nil
	case <-ctx.Done():
		close(w.cancelled)
		return ctx.Err()
	}
}
func workerDB(t *testing.T) *sql.DB {
	t.Helper()
	cfg, err := pgx.ParseConfig(os.Getenv("TEST_DATABASE_URL"))
	if os.Getenv("TEST_DATABASE_URL") == "" || err != nil {
		t.Fatal("valid TEST_DATABASE_URL required")
	}
	admin := stdlib.OpenDB(*cfg)
	schema := fmt.Sprintf("worker_%d", time.Now().UnixNano())
	if _, err = admin.Exec("CREATE SCHEMA " + schema); err != nil {
		t.Fatal(err)
	}
	cfg.RuntimeParams["search_path"] = schema + ",public"
	db := stdlib.OpenDB(*cfg)
	t.Cleanup(func() { db.Close(); admin.Exec("DROP SCHEMA " + schema + " CASCADE"); admin.Close() })
	if err = migrations.Up(context.Background(), db); err != nil {
		t.Fatal(err)
	}
	return db
}
func TestRiverMigrationReplayAndGracefulDrain(t *testing.T) {
	db := workerDB(t)
	ctx := context.Background()
	p := discovery.RankingPolicy{Version: "worker-v1", PriorStrength: 10, FallbackMean: .3, LikeHalfLifeDays: 30, MinSegmentDecisions: 200}
	projector, err := scores.New(db, p)
	if err != nil {
		t.Fatal(err)
	}
	missing, err := jobs.New(db, projector, jobs.Options{})
	if err != nil {
		t.Fatal(err)
	}
	if err = missing.Start(ctx); err == nil {
		drain, cancel := context.WithTimeout(ctx, time.Second)
		defer cancel()
		missing.Stop(drain)
		t.Fatal("started without River-owned migration")
	}
	if err = jobs.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	if err = jobs.Migrate(ctx, db); err != nil {
		t.Fatal("migration replay:", err)
	}
	fixture := &controlledWorker{entered: make(chan struct{}), release: make(chan struct{}), cancelled: make(chan struct{})}
	r, err := jobs.New(db, projector, jobs.Options{RegisterWorkers: func(w *river.Workers) { river.AddWorker(w, fixture) }})
	if err != nil {
		t.Fatal(err)
	}
	completed, unsubscribe := r.Client.Subscribe(river.EventKindJobCompleted)
	defer unsubscribe()
	for i := 0; i < 2; i++ {
		if _, err = r.Client.Insert(ctx, jobs.ScoreProjectArgs{}, nil); err != nil {
			t.Fatal(err)
		}
	}
	if _, err = r.Client.Insert(ctx, controlledArgs{}, nil); err != nil {
		t.Fatal(err)
	}
	run, cancelRun := context.WithCancel(ctx)
	defer cancelRun()
	if err = r.Start(run); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		closeIfOpen(fixture.release)
		drain, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()
		r.Stop(drain)
	})
	deadline := time.After(10 * time.Second)
	n := 0
	for n < 2 {
		select {
		case e := <-completed:
			if e.Job.Kind == "score_project" {
				n++
			}
		case <-deadline:
			t.Fatal("score job replay did not complete")
		}
	}
	select {
	case <-fixture.entered:
	case <-time.After(10 * time.Second):
		t.Fatal("controlled worker not started")
	}
	stopped := make(chan error, 1)
	go func() {
		drain, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()
		stopped <- r.Stop(drain)
	}()
	select {
	case err = <-stopped:
		t.Fatalf("drain returned before running job completed: %v", err)
	case <-fixture.cancelled:
		t.Fatal("in-flight job canceled during grace")
	case <-time.After(100 * time.Millisecond):
	}
	close(fixture.release)
	select {
	case err = <-stopped:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(6 * time.Second):
		t.Fatal("graceful stop blocked")
	}
}
func closeIfOpen(c chan struct{}) {
	select {
	case <-c:
	default:
		close(c)
	}
}
