//go:build integration

package limits_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"oma/apps/api/internal/platform/auth"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
	"oma/apps/api/internal/limits"
	"oma/apps/api/migrations"
)

const owner = "11111111-1111-4111-8111-111111111111"

func setup(t *testing.T) *sql.DB {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Fatal("TEST_DATABASE_URL must be disposable PostgreSQL/PostGIS")
	}
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	admin := stdlib.OpenDB(*cfg)
	schema := fmt.Sprintf("limits_%d", time.Now().UnixNano())
	if _, err = admin.Exec("CREATE SCHEMA " + schema); err != nil {
		t.Fatal(err)
	}
	cfg.RuntimeParams["search_path"] = schema + ",public"
	db := stdlib.OpenDB(*cfg)
	t.Cleanup(func() { db.Close(); admin.Exec("DROP SCHEMA " + schema + " CASCADE"); admin.Close() })
	if err = migrations.Up(context.Background(), db); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO accounts(user_id) VALUES($1)`, owner); err != nil {
		t.Fatal(err)
	}
	return db
}
func transaction(t *testing.T, db *sql.DB, f func(*sql.Tx)) {
	t.Helper()
	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	f(tx)
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
}
func service(t *testing.T) *limits.Service {
	t.Helper()
	s, err := limits.NewService(limits.Config{})
	if err != nil {
		t.Fatal(err)
	}
	return s
}
func TestDurableReservationReplayAndOriginalWIBDay(t *testing.T) {
	db := setup(t)
	s := service(t)
	ctx := context.Background()
	before := time.Date(2026, 11, 16, 16, 59, 59, 0, time.UTC)
	req := limits.Request{OwnerID: owner, OperationID: "22222222-2222-4222-8222-222222222222", Meter: limits.Searches, Units: 1, PayloadHash: "query-v1"}
	transaction(t, db, func(tx *sql.Tx) {
		r, err := s.ReserveTx(ctx, tx, req, before)
		if err != nil || r.Bucket != "2026-11-16" || r.State != "reserved" {
			t.Fatalf("reservation %+v %v", r, err)
		}
	})
	transaction(t, db, func(tx *sql.Tx) {
		u, err := s.UsageTx(ctx, tx, owner, before)
		if err != nil || u.Searches.Reserved != 1 || u.Searches.Available != 2 {
			t.Fatalf("usage %+v %v", u, err)
		}
		r, err := s.ReserveTx(ctx, tx, req, before.Add(time.Second))
		if err != nil || r.Bucket != "2026-11-16" {
			t.Fatalf("replay %+v %v", r, err)
		}
		changed := req
		changed.PayloadHash = "different"
		if _, err = s.ReserveTx(ctx, tx, changed, before); !errors.Is(err, limits.ErrConflict) {
			t.Fatalf("mismatch %v", err)
		}
		if _, err = s.ReleaseTx(ctx, tx, req); err != nil {
			t.Fatal(err)
		}
		if _, err = s.ReleaseTx(ctx, tx, req); err != nil {
			t.Fatal(err)
		}
		if _, err = s.SettleTx(ctx, tx, req); !errors.Is(err, limits.ErrConflict) {
			t.Fatalf("settled released hold: %v", err)
		}
		u, err = s.UsageTx(ctx, tx, owner, before.Add(time.Second))
		if err != nil || u.Searches.Available != 3 {
			t.Fatalf("new day %+v %v", u, err)
		}
		u, err = s.UsageTx(ctx, tx, owner, before)
		if err != nil || u.Searches.Available != 3 {
			t.Fatalf("old day %+v %v", u, err)
		}
	})
}

func TestConcurrentLastLikeAndSearchReservation(t *testing.T) {
	for _, meter := range []limits.Meter{limits.Likes, limits.Searches} {
		t.Run(string(meter), func(t *testing.T) {
			db := setup(t)
			s := service(t)
			ctx := context.Background()
			now := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
			units := 14
			if meter == limits.Searches {
				units = 2
			}
			transaction(t, db, func(tx *sql.Tx) {
				_, err := s.DebitTx(ctx, tx, limits.Request{OwnerID: owner, OperationID: "22222222-2222-4222-8222-222222222222", Meter: meter, Units: units, PayloadHash: "prior"}, now)
				if err != nil {
					t.Fatal(err)
				}
			})
			results := make(chan error, 2)
			for i := 3; i <= 4; i++ {
				go func(i int) {
					tx, err := db.Begin()
					if err != nil {
						results <- err
						return
					}
					defer tx.Rollback()
					_, err = s.ReserveTx(ctx, tx, limits.Request{OwnerID: owner, OperationID: fmt.Sprintf("%08d-3333-4333-8333-333333333333", i), Meter: meter, Units: 1, PayloadHash: "last"}, now)
					if err == nil {
						err = tx.Commit()
					}
					results <- err
				}(i)
			}
			success, exhausted := 0, 0
			for range 2 {
				err := <-results
				if err == nil {
					success++
				} else if errors.Is(err, limits.ErrLimit) {
					exhausted++
				} else {
					t.Fatal(err)
				}
			}
			if success != 1 || exhausted != 1 {
				t.Fatalf("success %d exhausted %d", success, exhausted)
			}
			transaction(t, db, func(tx *sql.Tx) {
				u, err := s.UsageTx(ctx, tx, owner, now)
				if err != nil {
					t.Fatal(err)
				}
				b := u.Likes
				if meter == limits.Searches {
					b = u.Searches
				}
				if b.Used != units || b.Reserved != 1 || b.Available != 0 {
					t.Fatalf("balance %+v", b)
				}
			})
		})
	}
}

func completeProfile(t *testing.T, db *sql.DB) {
	t.Helper()
	_, err := db.Exec(`INSERT INTO universities(name,country_code) VALUES('University','ID');
 INSERT INTO religions(code,label) VALUES('test','Test');
 INSERT INTO hobbies(category_id,code,label) SELECT id,'test','Test' FROM hobby_categories LIMIT 1;
 INSERT INTO profiles(user_id,full_name,birthdate,gender_id,pronoun_id,show_me_option_id,bio,height_cm,weight_kg,university_id,ambition,religion_id,personality_type_id)
 SELECT '11111111-1111-4111-8111-111111111111','Test User','2000-01-01',
 (SELECT id FROM gender_options LIMIT 1),(SELECT id FROM pronoun_options LIMIT 1),(SELECT id FROM show_me_options LIMIT 1),'Bio',170,65,
 (SELECT id FROM universities LIMIT 1),'Ambition',(SELECT id FROM religions LIMIT 1),(SELECT id FROM personality_types LIMIT 1);
 INSERT INTO profile_hobbies(user_id,hobby_id) SELECT '11111111-1111-4111-8111-111111111111',id FROM hobbies LIMIT 1;
 INSERT INTO photos(user_id,storage_path,content_type,file_size,position,status) VALUES('11111111-1111-4111-8111-111111111111','fixture/photo.jpg','image/jpeg',1,1,'active')`)
	if err != nil {
		t.Fatal(err)
	}
}
func TestCompletionUpgradeAndDowngradeKeepOriginalHolds(t *testing.T) {
	db := setup(t)
	s := service(t)
	ctx := context.Background()
	now := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	transaction(t, db, func(tx *sql.Tx) {
		_, err := s.DebitTx(ctx, tx, limits.Request{OwnerID: owner, OperationID: "22222222-2222-4222-8222-222222222222", Meter: limits.Likes, Units: 15, PayloadHash: "prior"}, now)
		if err != nil {
			t.Fatal(err)
		}
	})
	completeProfile(t, db)
	req := limits.Request{OwnerID: owner, OperationID: "33333333-3333-4333-8333-333333333333", Meter: limits.Likes, Units: 5, PayloadHash: "pending"}
	transaction(t, db, func(tx *sql.Tx) {
		u, err := s.UsageTx(ctx, tx, owner, now)
		if err != nil || !u.ProfileComplete || u.Likes.Limit != 30 || u.Likes.Available != 15 {
			t.Fatalf("upgrade %+v %v", u, err)
		}
		if _, err = s.ReserveTx(ctx, tx, req, now); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := db.Exec(`UPDATE profiles SET ambition=NULL WHERE user_id=$1`, owner); err != nil {
		t.Fatal(err)
	}
	transaction(t, db, func(tx *sql.Tx) {
		u, err := s.UsageTx(ctx, tx, owner, now)
		if err != nil || u.ProfileComplete || u.Likes.Limit != 20 || u.Likes.Available != 0 || u.Likes.Reserved != 5 {
			t.Fatalf("downgrade %+v %v", u, err)
		}
		if _, err = s.SettleTx(ctx, tx, req); err != nil {
			t.Fatal(err)
		}
		if _, err = s.DebitTx(ctx, tx, req, now.Add(24*time.Hour)); err != nil {
			t.Fatal(err)
		}
		u, err = s.UsageTx(ctx, tx, owner, now)
		if err != nil || u.Likes.Used != 20 || u.Likes.Reserved != 0 {
			t.Fatalf("settled %+v %v", u, err)
		}
		u, err = s.UsageTx(ctx, tx, owner, now.Add(24*time.Hour))
		if err != nil || u.Likes.Available != 15 {
			t.Fatalf("next day %+v %v", u, err)
		}
	})
}

type identity struct{}

func (identity) Verify(_ context.Context, token string) (string, error) {
	if token == "owner" {
		return owner, nil
	}
	return "", errors.New("unauthorized")
}
func TestUsageHTTPTrustsOnlyServerPROAllowlist(t *testing.T) {
	db := setup(t)
	free := service(t)
	pro, err := limits.NewService(limits.Config{Environment: "development", DevelopmentPROUserIDs: []string{owner}})
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		service          *limits.Service
		path, token      string
		status, searches int
	}{{free, "/v1/me/usage", "owner", 200, 3}, {pro, "/v1/me/usage", "owner", 200, 20}, {free, "/v1/me/usage?pro=true", "owner", 400, 0}, {free, "/v1/me/usage?user_id=another", "owner", 400, 0}, {pro, "/v1/me/usage", "invalid", 401, 0}} {
		h := auth.Middleware(identity{}, tc.service.HandlerUsage(db))
		r := httptest.NewRequest(http.MethodGet, tc.path, nil)
		r.Header.Set("Authorization", "Bearer "+tc.token)
		r.Header.Set("X-Pro", "true")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != tc.status {
			t.Fatalf("%s status %d: %s", tc.path, w.Code, w.Body)
		}
		if tc.status == 200 {
			var out struct {
				Data limits.Usage `json:"data"`
			}
			if err = json.Unmarshal(w.Body.Bytes(), &out); err != nil {
				t.Fatal(err)
			}
			if out.Data.Searches.Limit != tc.searches {
				t.Fatalf("usage %+v", out)
			}
		}
	}
}

func TestCallerRollbackRestoresCapacityAndAllowsRetry(t *testing.T) {
	db := setup(t)
	s := service(t)
	ctx := context.Background()
	now := time.Now()
	req := limits.Request{OwnerID: owner, OperationID: "22222222-2222-4222-8222-222222222222", Meter: limits.Searches, Units: 3, PayloadHash: "query"}
	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.DebitTx(ctx, tx, req, now); err != nil {
		t.Fatal(err)
	}
	if err = tx.Rollback(); err != nil {
		t.Fatal(err)
	}
	transaction(t, db, func(tx *sql.Tx) {
		u, err := s.UsageTx(ctx, tx, owner, now)
		if err != nil || u.Searches.Available != 3 {
			t.Fatalf("rollback %+v %v", u, err)
		}
		if _, err = s.DebitTx(ctx, tx, req, now); err != nil {
			t.Fatal(err)
		}
		if _, err = s.DebitTx(ctx, tx, req, now); err != nil {
			t.Fatal(err)
		}
		u, err = s.UsageTx(ctx, tx, owner, now)
		if err != nil || u.Searches.Used != 3 || u.Searches.Available != 0 {
			t.Fatalf("retry %+v %v", u, err)
		}
	})
}
