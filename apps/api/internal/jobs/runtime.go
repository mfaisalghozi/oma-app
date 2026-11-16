package jobs

import (
	"context"
	"database/sql"
	"errors"
	"github.com/riverqueue/river"
	"github.com/riverqueue/river/riverdriver/riverdatabasesql"
	"github.com/riverqueue/river/rivermigrate"
	"github.com/riverqueue/river/rivertype"
	"log/slog"
	"oma/apps/api/internal/limits"
	"oma/apps/api/internal/scores"
	"time"
)

type ScoreProjectArgs struct{}

func (ScoreProjectArgs) Kind() string { return "score_project" }

type NightlyArgs struct{}

func (NightlyArgs) Kind() string { return "nightly" }

type Options struct {
	RegisterWorkers func(*river.Workers)
	Reconcile       func(context.Context) error
}
type Runtime struct {
	Client  *river.Client[*sql.Tx]
	scores  *scores.Service
	options Options
	cancel  context.CancelFunc
	done    chan struct{}
}
type projectWorker struct {
	river.WorkerDefaults[ScoreProjectArgs]
	runtime *Runtime
}

func (w *projectWorker) Work(ctx context.Context, _ *river.Job[ScoreProjectArgs]) error {
	_, err := w.runtime.scores.Project(ctx, time.Now().UTC(), false)
	return err
}

type nightlyWorker struct {
	river.WorkerDefaults[NightlyArgs]
	runtime *Runtime
}

func (w *nightlyWorker) Work(ctx context.Context, _ *river.Job[NightlyArgs]) error {
	_, err := w.runtime.scores.Project(ctx, time.Now().UTC(), true)
	return err
}
func (w *nightlyWorker) Timeout(*river.Job[NightlyArgs]) time.Duration { return 10 * time.Minute }

type nightlySchedule struct{}

func (nightlySchedule) Next(t time.Time) time.Time { return NextNightly(t) }
func NextNightly(now time.Time) time.Time          { _, reset := limits.Bucket(now); return reset }
func uniqueOpts() *river.InsertOpts {
	return &river.InsertOpts{UniqueOpts: river.UniqueOpts{ByArgs: true, ByState: []rivertype.JobState{rivertype.JobStateAvailable, rivertype.JobStatePending, rivertype.JobStateRunning, rivertype.JobStateRetryable, rivertype.JobStateScheduled}}}
}
func New(db *sql.DB, projector *scores.Service, options Options) (*Runtime, error) {
	if db == nil || projector == nil {
		return nil, errors.New("score worker dependencies required")
	}
	r := &Runtime{scores: projector, options: options, done: make(chan struct{})}
	workers := river.NewWorkers()
	river.AddWorker(workers, &projectWorker{runtime: r})
	river.AddWorker(workers, &nightlyWorker{runtime: r})
	if options.RegisterWorkers != nil {
		options.RegisterWorkers(workers)
	}
	client, err := river.NewClient(riverdatabasesql.New(db), &river.Config{Workers: workers, Queues: map[string]river.QueueConfig{river.QueueDefault: {MaxWorkers: 4}}, PollOnly: true, FetchPollInterval: time.Second, JobTimeout: 30 * time.Second, PeriodicJobs: []*river.PeriodicJob{
		river.NewPeriodicJob(river.PeriodicInterval(time.Second), func() (river.JobArgs, *river.InsertOpts) { return ScoreProjectArgs{}, uniqueOpts() }, &river.PeriodicJobOpts{RunOnStart: true}),
		river.NewPeriodicJob(nightlySchedule{}, func() (river.JobArgs, *river.InsertOpts) { return NightlyArgs{}, uniqueOpts() }, nil),
	}})
	if err != nil {
		return nil, err
	}
	r.Client = client
	return r, nil
}
func Migrate(ctx context.Context, db *sql.DB) error {
	m, err := rivermigrate.New(riverdatabasesql.New(db), nil)
	if err != nil {
		return err
	}
	_, err = m.Migrate(ctx, rivermigrate.DirectionUp, nil)
	return err
}
func (r *Runtime) Reconcile(ctx context.Context) error {
	var failures []error
	// Lease cleanup must run even when an unrelated queue insertion fails.
	if r.options.Reconcile != nil {
		if err := r.options.Reconcile(ctx); err != nil {
			failures = append(failures, err)
		}
	}
	if _, err := r.Client.Insert(ctx, ScoreProjectArgs{}, uniqueOpts()); err != nil {
		failures = append(failures, err)
	}
	due, err := r.scores.NightlyDue(ctx, time.Now().UTC())
	if err != nil {
		failures = append(failures, err)
	} else if due {
		if _, err = r.Client.Insert(ctx, NightlyArgs{}, uniqueOpts()); err != nil {
			failures = append(failures, err)
		}
	}
	return errors.Join(failures...)
}

func (r *Runtime) Start(ctx context.Context) error {
	if err := r.Client.Start(ctx); err != nil {
		return err
	}
	runCtx, cancel := context.WithCancel(ctx)
	r.cancel = cancel
	go func() {
		defer close(r.done)
		ticker := time.NewTicker(60 * time.Second)
		defer ticker.Stop()
		reconcile := func() {
			if err := r.Reconcile(runCtx); err != nil && runCtx.Err() == nil {
				slog.Error("worker reconciliation failed")
			}
		}
		reconcile()
		for {
			select {
			case <-runCtx.Done():
				return
			case <-ticker.C:
				reconcile()
			}
		}
	}()
	return nil
}
func (r *Runtime) Stop(ctx context.Context) error {
	if r.cancel != nil {
		r.cancel()
	}
	err := r.Client.Stop(ctx)
	if err != nil {
		force, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		_ = r.Client.StopAndCancel(force)
	}
	if r.cancel != nil {
		select {
		case <-r.done:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return err
}
