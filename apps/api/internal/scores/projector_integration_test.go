//go:build integration

package scores_test

import (
	"context"
	"database/sql"
	"fmt"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
	"math"
	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/scores"
	"oma/apps/api/migrations"
	"os"
	"testing"
	"time"
)

const candidate = "22222222-2222-4222-8222-222222222222"
const actor = "11111111-1111-4111-8111-111111111111"

func setup(t *testing.T) (*sql.DB, *scores.Service, time.Time) {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Fatal("TEST_DATABASE_URL required")
	}
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	admin := stdlib.OpenDB(*cfg)
	schema := fmt.Sprintf("scores_%d", time.Now().UnixNano())
	if _, err = admin.Exec("CREATE SCHEMA " + schema); err != nil {
		t.Fatal(err)
	}
	cfg.RuntimeParams["search_path"] = schema + ",public"
	db := stdlib.OpenDB(*cfg)
	t.Cleanup(func() { db.Close(); admin.Exec("DROP SCHEMA " + schema + " CASCADE"); admin.Close() })
	if err = migrations.Up(context.Background(), db); err != nil {
		t.Fatal(err)
	}
	p := discovery.RankingPolicy{Version: "test-v1", PriorStrength: 10, FallbackMean: .3, LikeHalfLifeDays: 30, MinSegmentDecisions: 200}
	s, err := scores.New(db, p)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC().Truncate(time.Second)
	if _, err = db.Exec(`INSERT INTO accounts(user_id,created_at,phone_verified_at) VALUES($1,$3::timestamptz-interval '10 days',$3::timestamptz-interval '10 days'),($2,$3::timestamptz-interval '10 days',NULL)`, actor, candidate, now); err != nil {
		t.Fatal(err)
	}
	return db, s, now
}
func event(t *testing.T, db interface {
	Exec(string, ...any) (sql.Result, error)
}, id int64, from, to, action string, at time.Time) {
	t.Helper()
	_, err := db.Exec(`WITH interaction AS(INSERT INTO profile_interactions(actor_id,target_id,action,context_kind,context_id,created_at) VALUES($1,$2,$3,'regular_deck',gen_random_uuid(),$4) RETURNING id) INSERT INTO swipe_events(id,action_id,actor_id,target_id,action,segment_key,occurred_at) SELECT $5,id,$1,$2,$3,'male:female',$4 FROM interaction`, from, to, action, at, id)
	if err != nil {
		t.Fatal(err)
	}
}
func project(t *testing.T, s *scores.Service, now time.Time, nightly bool) scores.Result {
	t.Helper()
	r, err := s.Project(context.Background(), now, nightly)
	if err != nil {
		t.Fatal(err)
	}
	return r
}
func quality(t *testing.T, s *scores.Service) scores.Quality {
	t.Helper()
	q, err := s.Lookup(context.Background(), candidate, "male:female")
	if err != nil {
		t.Fatal(err)
	}
	return q
}
func TestReplayAndLowerIDCommittingAfterHigherID(t *testing.T) {
	db, s, now := setup(t)
	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	event(t, tx, 1, actor, candidate, "like", now)
	other := "33333333-3333-4333-8333-333333333333"
	if _, err = db.Exec(`INSERT INTO accounts(user_id,created_at,phone_verified_at) VALUES($1,$2::timestamptz-interval '10 days',$2)`, other, now); err != nil {
		t.Fatal(err)
	}
	event(t, db, 2, other, candidate, "pass", now)
	if got := project(t, s, now, false); got.Claimed != 1 {
		t.Fatalf("first %+v", got)
	}
	if got := project(t, s, now, false); got.Claimed != 0 {
		t.Fatalf("replay %+v", got)
	}
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
	if got := project(t, s, now, false); got.Claimed != 1 {
		t.Fatalf("late event %+v", got)
	}
	q := quality(t, s)
	if q.Likes != .25 || q.Passes != 1 || q.PriorMean != .3 {
		t.Fatalf("late commit quality %+v", q)
	}
	if got := project(t, s, now, false); got.Claimed != 0 {
		t.Fatalf("duplicate %+v", got)
	}
	if quality(t, s) != q {
		t.Fatal("replay changed score")
	}
	project(t, s, now, true)
	if _, err = db.Exec(`UPDATE accounts SET status='suspended' WHERE user_id=$1`, actor); err != nil {
		t.Fatal(err)
	}
	project(t, s, now, true)
	if q = quality(t, s); q.Likes != 0 || q.Passes != 1 {
		t.Fatalf("suspended actor remained %+v", q)
	}
	if _, err = db.Exec(`UPDATE swipe_events SET action='pass' WHERE id=1`); err == nil {
		t.Fatal("source event mutated")
	}
}
func TestBatchBoundAndDecayAndPaidPositiveEquality(t *testing.T) {
	db, s, now := setup(t)
	_, err := db.Exec(`WITH actors AS(INSERT INTO accounts(user_id,created_at,phone_verified_at) SELECT gen_random_uuid(),$2::timestamptz-interval '40 days',$2 FROM generate_series(1,1001) RETURNING user_id),interactions AS(INSERT INTO profile_interactions(actor_id,target_id,action,context_kind,context_id,created_at) SELECT user_id,$1,CASE WHEN row_number() OVER() % 2=0 THEN 'like' ELSE 'super_like' END,'regular_deck',gen_random_uuid(),$2::timestamptz-interval '30 days' FROM actors RETURNING *) INSERT INTO swipe_events(action_id,actor_id,target_id,action,segment_key,occurred_at) SELECT id,actor_id,target_id,action,'male:female',created_at FROM interactions`, candidate, now)
	if err != nil {
		t.Fatal(err)
	}
	if got := project(t, s, now, false); got.Claimed != 1000 {
		t.Fatalf("batch %+v", got)
	}
	if got := project(t, s, now, false); got.Claimed != 1 {
		t.Fatalf("remaining %+v", got)
	}
	if got := quality(t, s); math.Abs(got.Likes-125.125) > 1e-9 || got.Passes != 0 {
		t.Fatalf("paid and free must each contribute .25*.5: %+v", got)
	}
	if got := project(t, s, now, false); got.Claimed != 0 {
		t.Fatalf("replayed backlog %+v", got)
	}
	project(t, s, now.Add(121*24*time.Hour), true)
	if got := quality(t, s); got.Likes != 0 || got.Passes != 0 || got.PriorMean != .3 {
		t.Fatalf("expired evidence %+v", got)
	}
}

func TestNightlyPublishesPriorsPercentilesAndReplyMetadata(t *testing.T) {
	db, s, now := setup(t)
	other := "33333333-3333-4333-8333-333333333333"
	if _, err := db.Exec(`INSERT INTO accounts(user_id) VALUES($1)`, other); err != nil {
		t.Fatal(err)
	}
	event(t, db, 1, actor, candidate, "like", now)
	event(t, db, 2, actor, other, "pass", now)
	project(t, s, now, false)
	if q := quality(t, s); q.Percentile != .5 || q.CompletedMatches != 0 || q.ReplyRate != .75 {
		t.Fatalf("cold reply and percentile priors %+v", q)
	}
	var match string
	if err := db.QueryRow(`INSERT INTO matches(user_low,user_high,created_at) VALUES($1,$2,$3) RETURNING id`, actor, candidate, now.Add(-96*time.Hour)).Scan(&match); err != nil {
		t.Fatal(err)
	}
	opened := now.Add(-72 * time.Hour)
	reply := opened.Add(time.Hour)
	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	window := scores.ReplyWindow{MatchID: match, OpenerSenderID: actor, OpenedAt: opened, FirstReplyAt: &reply}
	if err = scores.RecordReplyWindowTx(context.Background(), tx, window); err != nil {
		t.Fatal(err)
	}
	if err = scores.RecordReplyWindowTx(context.Background(), tx, window); err != nil {
		t.Fatal("metadata replay", err)
	}
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
	s, err = scores.New(db, discovery.RankingPolicy{Version: "priors-v2", PriorStrength: 10, FallbackMean: .3, LikeHalfLifeDays: 30, MinSegmentDecisions: 1})
	if err != nil {
		t.Fatal(err)
	}
	if due, err := s.NightlyDue(context.Background(), now); err != nil || !due {
		t.Fatalf("missing nightly due=%v %v", due, err)
	}
	project(t, s, now, true)
	q := quality(t, s)
	if q.PriorMean != .5 || q.Percentile != 1 || q.CompletedMatches != 1 || q.ReplyRate != .8 {
		t.Fatalf("nightly quality %+v", q)
	}
	lower, err := s.Lookup(context.Background(), other, "male:female")
	if err != nil || lower.Percentile != 0 {
		t.Fatalf("lower percentile %+v %v", lower, err)
	}
	if due, err := s.NightlyDue(context.Background(), now); err != nil || due {
		t.Fatalf("completed nightly due=%v %v", due, err)
	}
	if due, err := s.NightlyDue(context.Background(), now.Add(24*time.Hour)); err != nil || !due {
		t.Fatalf("next WIB day due=%v %v", due, err)
	}
	tx, err = db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	if err = scores.RecordPhoneVerificationTx(context.Background(), tx, actor, nil); err != nil {
		t.Fatal(err)
	}
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
	project(t, s, now, true)
	if q = quality(t, s); q.Likes != 0 || q.PriorMean != .3 {
		t.Fatalf("unverified actor reset %+v", q)
	}
}
