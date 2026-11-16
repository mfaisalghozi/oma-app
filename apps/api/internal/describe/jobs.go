package describe

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/riverqueue/river"
	"github.com/riverqueue/river/riverdriver/riverdatabasesql"
)

type SearchArgs struct {
	SearchID string `json:"search_id"`
}

func (SearchArgs) Kind() string { return "describe_search" }
func (SearchArgs) InsertOpts() river.InsertOpts {
	return river.InsertOpts{MaxAttempts: 3, UniqueOpts: river.UniqueOpts{ByArgs: true}}
}

type SearchWorker struct {
	river.WorkerDefaults[SearchArgs]
	Service *Service
}

func (w *SearchWorker) Work(ctx context.Context, job *river.Job[SearchArgs]) error {
	return w.Service.Run(ctx, job.Args.SearchID)
}
func (w *SearchWorker) Timeout(*river.Job[SearchArgs]) time.Duration { return 35 * time.Second }
func (s *Service) RegisterWorkers(workers *river.Workers) {
	river.AddWorker(workers, &SearchWorker{Service: s})
}
func NewInsertClient(db *sql.DB) (*river.Client[*sql.Tx], error) {
	return river.NewClient(riverdatabasesql.New(db), &river.Config{})
}

func (s *Service) Reconcile(ctx context.Context) error {
	// Refund expired workers even when queue insertion is unavailable.
	if err := s.reconcileExpired(ctx); err != nil {
		return err
	}
	if _, err := s.PruneRequestKeys(ctx); err != nil {
		return err
	}
	if s.Client == nil {
		return errors.New("Describe queue unavailable")
	}
	rows, err := s.DB.QueryContext(ctx, `SELECT id FROM describe_searches WHERE state='pending' ORDER BY created_at LIMIT 100`)
	if err != nil {
		return err
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if err = rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		ids = append(ids, id)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	var failures []error
	for _, id := range ids {
		if _, err = s.Client.Insert(ctx, SearchArgs{SearchID: id}, nil); err != nil {
			failures = append(failures, err)
		}
	}
	return errors.Join(failures...)
}
