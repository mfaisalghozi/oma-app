package describe

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"time"

	"oma/apps/api/internal/limits"
)

type attempt struct{ owner, id, key, hash, query, token string }

// Run claims a fenced lease; model IO never holds an account or database lock.
func (s *Service) Run(ctx context.Context, id string) error {
	a, err := s.claim(ctx, id)
	if err != nil || a.token == "" {
		return err
	}
	work, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	var c Criteria
	if !s.configured() {
		err = ErrProvider
	} else {
		c, err = s.Parser.Parse(work, a.query)
	}
	result := Retrieval{Criteria: c}
	if err == nil {
		raw, _ := json.Marshal(c)
		_, err = s.DB.ExecContext(work, `UPDATE describe_searches SET phase='retrieving',criteria=$3 WHERE id=$1 AND lease_token=$2 AND state='running'`, a.id, a.token, raw)
	}
	if err == nil {
		result, err = s.Retriever.Retrieve(work, a.owner, c)
	}
	code := ""
	if err != nil {
		code = "SEARCH_FAILED"
		if errors.Is(err, ErrInvalidCriteria) || errors.Is(err, ErrNoSearchableCriteria) {
			code = "INVALID_SEARCH_QUERY"
		}
	}
	if work.Err() != nil {
		code = "SEARCH_FAILED"
	}
	// Finalization survives job cancellation; a restart is reconciled from the durable lease.
	finish, cancelFinish := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancelFinish()
	return s.finish(finish, a, result, code)
}
func (s *Service) claim(ctx context.Context, id string) (attempt, error) {
	a := attempt{id: id}
	err := s.DB.QueryRowContext(ctx, `SELECT owner_id FROM describe_searches WHERE id=$1`, id).Scan(&a.owner)
	if err == sql.ErrNoRows {
		return a, nil
	}
	if err != nil {
		return a, err
	}
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return a, err
	}
	defer tx.Rollback()
	var lock string
	if err = tx.QueryRowContext(ctx, `SELECT user_id FROM accounts WHERE user_id=$1 FOR UPDATE`, a.owner).Scan(&lock); err != nil {
		return a, err
	}
	err = tx.QueryRowContext(ctx, `UPDATE describe_searches SET state='running',phase='parsing',lease_token=gen_random_uuid(),lease_until=$2 WHERE id=$1 AND state='pending' RETURNING request_id,payload_hash,query,lease_token`, id, s.now().Add(30*time.Second)).Scan(&a.key, &a.hash, &a.query, &a.token)
	if err == sql.ErrNoRows {
		return a, nil
	}
	if err != nil {
		return a, err
	}
	return a, tx.Commit()
}
func (s *Service) finish(ctx context.Context, a attempt, result Retrieval, code string) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var lock string
	if err = tx.QueryRowContext(ctx, `SELECT user_id FROM accounts WHERE user_id=$1 FOR UPDATE`, a.owner).Scan(&lock); err != nil {
		return err
	}
	var alive bool
	err = tx.QueryRowContext(ctx, `SELECT lease_until>$3 FROM describe_searches WHERE id=$1 AND state='running' AND lease_token=$2 FOR UPDATE`, a.id, a.token, s.now()).Scan(&alive)
	if err == sql.ErrNoRows {
		return nil
	}
	if err != nil {
		return err
	}
	if !alive {
		code = "SEARCH_FAILED"
	}
	req := limits.Request{OwnerID: a.owner, OperationID: a.key, Meter: limits.Searches, Units: 1, PayloadHash: a.hash}
	if code != "" {
		if result.Criteria.Version != "" {
			raw, e := json.Marshal(result.Criteria)
			if e != nil {
				return e
			}
			if _, e = tx.ExecContext(ctx, `UPDATE describe_searches SET criteria=$2 WHERE id=$1`, a.id, raw); e != nil {
				return e
			}
		}
		if _, err = s.Limits.ReleaseTx(ctx, tx, req); err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `UPDATE describe_searches SET state='failed',error_code=$2,completed_at=$3,lease_token=NULL,lease_until=NULL WHERE id=$1`, a.id, code, s.now())
	} else {
		var raw []byte
		raw, err = json.Marshal(result.Criteria)
		if err != nil {
			return err
		}
		if _, err = s.Limits.SettleTx(ctx, tx, req); err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `UPDATE describe_searches SET state='succeeded',criteria=$2,requested_radius_km=$3,effective_radius_km=$4,completed_at=$5,lease_token=NULL,lease_until=NULL WHERE id=$1`, a.id, raw, result.RequestedRadiusKM, result.EffectiveRadiusKM, s.now())
		if err != nil {
			return err
		}
		for i, v := range result.Results {
			raw, err = json.Marshal(v.Evaluation)
			if err != nil {
				return err
			}
			if _, err = tx.ExecContext(ctx, `INSERT INTO describe_search_results(search_id,candidate_id,position,profile_revision,evaluation) VALUES($1,$2,$3,$4,$5)`, a.id, v.Profile.ID, i+1, v.Profile.Revision, raw); err != nil {
				return err
			}
		}
	}
	if err != nil {
		return err
	}
	return tx.Commit()
}

// A crashed worker refunds its original WIB hold when its durable lease expires.
func (s *Service) reconcileExpired(ctx context.Context) error {
	rows, err := s.DB.QueryContext(ctx, `SELECT id,owner_id,request_id,payload_hash,lease_token FROM describe_searches WHERE state='running' AND lease_until<=$1`, s.now())
	if err != nil {
		return err
	}
	attempts := []attempt{}
	for rows.Next() {
		var a attempt
		if err = rows.Scan(&a.id, &a.owner, &a.key, &a.hash, &a.token); err != nil {
			rows.Close()
			return err
		}
		attempts = append(attempts, a)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, a := range attempts {
		if err = s.finish(ctx, a, Retrieval{}, "SEARCH_FAILED"); err != nil {
			return err
		}
	}
	return nil
}
