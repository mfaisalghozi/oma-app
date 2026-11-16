package limits

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"oma/apps/api/internal/platform/httpapi"
)

type Meter string

const (
	Likes    Meter = "likes"
	Searches Meter = "searches"
)

var (
	ErrLimit    = errors.New("daily limit exhausted")
	ErrConflict = errors.New("limit operation conflicts with original request or terminal state")
	ErrInvalid  = errors.New("invalid limit operation")
)

type Request struct {
	OwnerID, OperationID string
	Meter                Meter
	Units                int
	PayloadHash          string
}
type Reservation struct {
	OperationID string `json:"operation_id"`
	Meter       Meter  `json:"meter"`
	Bucket      string `json:"bucket"`
	Units       int    `json:"units"`
	State       string `json:"state"`
}
type Balance struct {
	Limit     int `json:"limit"`
	Used      int `json:"used"`
	Reserved  int `json:"reserved"`
	Available int `json:"available"`
}
type Usage struct {
	Bucket          string    `json:"bucket"`
	ResetsAt        time.Time `json:"resets_at"`
	PRO             bool      `json:"pro"`
	ProfileComplete bool      `json:"profile_complete"`
	Likes           Balance   `json:"likes"`
	Searches        Balance   `json:"searches"`
}

// The account lock is shared with profile edits so grants and consumption agree.
func lockOwner(ctx context.Context, tx *sql.Tx, id string) error {
	if !httpapi.ValidID(id) {
		return ErrInvalid
	}
	var found string
	return tx.QueryRowContext(ctx, `SELECT user_id FROM accounts WHERE user_id=$1 FOR UPDATE`, id).Scan(&found)
}

func (s *Service) UsageTx(ctx context.Context, tx *sql.Tx, owner string, now time.Time) (Usage, error) {
	if err := lockOwner(ctx, tx, owner); err != nil {
		return Usage{}, err
	}
	return s.usage(ctx, tx, owner, now)
}

func (s *Service) usage(ctx context.Context, tx *sql.Tx, owner string, now time.Time) (Usage, error) {
	day, reset := Bucket(now)
	u := Usage{Bucket: day, ResetsAt: reset, PRO: s.pro[strings.ToLower(owner)]}
	err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM profiles p WHERE p.user_id=$1
 AND btrim(p.full_name)<>'' AND btrim(p.bio)<>''
 AND p.university_id IS NOT NULL AND p.ambition IS NOT NULL AND btrim(p.ambition)<>''
 AND p.religion_id IS NOT NULL AND p.personality_type_id IS NOT NULL AND p.pronoun_id IS NOT NULL
 AND EXISTS(SELECT 1 FROM photos WHERE user_id=p.user_id AND status='active')
 AND EXISTS(SELECT 1 FROM profile_hobbies WHERE user_id=p.user_id))`, owner).Scan(&u.ProfileComplete)
	if err != nil {
		return u, err
	}
	rows, err := tx.QueryContext(ctx, `SELECT meter,COALESCE(sum(units) FILTER(WHERE state='settled'),0),COALESCE(sum(units) FILTER(WHERE state='reserved'),0) FROM daily_limit_operations WHERE owner_id=$1 AND bucket=$2 GROUP BY meter`, owner, day)
	if err != nil {
		return u, err
	}
	defer rows.Close()
	for rows.Next() {
		var meter Meter
		var used, reserved int
		if err = rows.Scan(&meter, &used, &reserved); err != nil {
			return u, err
		}
		b := &u.Likes
		if meter == Searches {
			b = &u.Searches
		}
		b.Used = used
		b.Reserved = reserved
	}
	if err = rows.Err(); err != nil {
		return u, err
	}
	g := Grants(u.ProfileComplete, u.PRO)
	u.Likes = balance(u.Likes, g.Likes)
	u.Searches = balance(u.Searches, g.Searches)
	return u, nil
}
func balance(b Balance, grant int) Balance {
	b.Limit = max(grant, b.Used+b.Reserved)
	b.Available = b.Limit - b.Used - b.Reserved
	return b
}
func valid(req Request) bool {
	return httpapi.ValidID(req.OwnerID) && httpapi.ValidID(req.OperationID) && (req.Meter == Likes || req.Meter == Searches) && req.Units > 0 && len(req.PayloadHash) > 0 && len(req.PayloadHash) <= 256
}
func original(ctx context.Context, tx *sql.Tx, req Request) (Reservation, error) {
	r := Reservation{OperationID: strings.ToLower(req.OperationID), Meter: req.Meter}
	var hash string
	err := tx.QueryRowContext(ctx, `SELECT bucket::text,units,state,payload_hash FROM daily_limit_operations WHERE owner_id=$1 AND meter=$2 AND operation_id=$3`, req.OwnerID, req.Meter, req.OperationID).Scan(&r.Bucket, &r.Units, &r.State, &hash)
	if err == nil && (r.Units != req.Units || hash != req.PayloadHash) {
		return Reservation{}, ErrConflict
	}
	return r, err
}

// ReserveTx must share the caller's action/search transaction; retries keep their original bucket.
func (s *Service) ReserveTx(ctx context.Context, tx *sql.Tx, req Request, now time.Time) (Reservation, error) {
	if !valid(req) {
		return Reservation{}, ErrInvalid
	}
	if err := lockOwner(ctx, tx, req.OwnerID); err != nil {
		return Reservation{}, err
	}
	r, err := original(ctx, tx, req)
	if err == nil {
		return r, nil
	}
	if err != sql.ErrNoRows {
		return Reservation{}, err
	}
	u, err := s.usage(ctx, tx, req.OwnerID, now)
	if err != nil {
		return Reservation{}, err
	}
	b := u.Likes
	if req.Meter == Searches {
		b = u.Searches
	}
	if req.Units > b.Available {
		return Reservation{}, ErrLimit
	}
	r = Reservation{OperationID: strings.ToLower(req.OperationID), Meter: req.Meter, Bucket: u.Bucket, Units: req.Units, State: "reserved"}
	_, err = tx.ExecContext(ctx, `INSERT INTO daily_limit_operations(owner_id,meter,operation_id,bucket,units,payload_hash,state) VALUES($1,$2,$3,$4,$5,$6,'reserved')`, req.OwnerID, req.Meter, req.OperationID, r.Bucket, req.Units, req.PayloadHash)
	return r, err
}
func (s *Service) transition(ctx context.Context, tx *sql.Tx, req Request, state string) (Reservation, error) {
	if !valid(req) {
		return Reservation{}, ErrInvalid
	}
	if err := lockOwner(ctx, tx, req.OwnerID); err != nil {
		return Reservation{}, err
	}
	r, err := original(ctx, tx, req)
	if err != nil {
		return Reservation{}, err
	}
	if r.State == state {
		return r, nil
	}
	if r.State != "reserved" {
		return Reservation{}, ErrConflict
	}
	_, err = tx.ExecContext(ctx, `UPDATE daily_limit_operations SET state=$4 WHERE owner_id=$1 AND meter=$2 AND operation_id=$3`, req.OwnerID, req.Meter, req.OperationID, state)
	r.State = state
	return r, err
}
func (s *Service) SettleTx(ctx context.Context, tx *sql.Tx, req Request) (Reservation, error) {
	return s.transition(ctx, tx, req, "settled")
}
func (s *Service) ReleaseTx(ctx context.Context, tx *sql.Tx, req Request) (Reservation, error) {
	return s.transition(ctx, tx, req, "released")
}
func (s *Service) DebitTx(ctx context.Context, tx *sql.Tx, req Request, now time.Time) (Reservation, error) {
	if _, err := s.ReserveTx(ctx, tx, req, now); err != nil {
		return Reservation{}, err
	}
	return s.SettleTx(ctx, tx, req)
}
