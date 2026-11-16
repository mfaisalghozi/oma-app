//go:build integration

package api_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"oma/apps/api/internal/limits"
	"strings"
	"testing"
	"time"
)

func swipe(t *testing.T, h http.Handler, actor, key, body string, status int) map[string]any {
	t.Helper()
	r := httptest.NewRequest("POST", "/v1/discovery/actions", strings.NewReader(body))
	r.Header.Set("Authorization", "Bearer "+actor)
	r.Header.Set("Idempotency-Key", key)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != status {
		t.Fatalf("swipe got%d want%d: %s", w.Code, status, w.Body.String())
	}
	var out map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	return out
}
func swipeBody(target, context, action string) string {
	return fmt.Sprintf(`{"target_id":%q,"context_id":%q,"context_kind":"regular_deck","action":%q}`, target, context, action)
}
func TestSwipePassIsIrreversibleAndAliasesNewKeys(t *testing.T) {
	_, h := deckSetup(t)
	d := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)
	body := swipeBody(bob, d["context_id"].(string), "pass")
	first := swipe(t, h, "alice", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", body, 200)
	replay := swipe(t, h, "alice", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", body, 200)
	alias := swipe(t, h, "alice", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", body, 200)
	if fmt.Sprint(first) != fmt.Sprint(replay) || fmt.Sprint(first) != fmt.Sprint(alias) {
		t.Fatal("replay changed response")
	}
	swipe(t, h, "alice", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", swipeBody(bob, d["context_id"].(string), "like"), 409)
	swipe(t, h, "alice", "cccccccc-cccc-4ccc-8ccc-cccccccccccc", swipeBody(bob, d["context_id"].(string), "like"), 409)
	next := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)
	if len(next["cards"].([]any)) != 0 {
		t.Fatal("decided profile returned")
	}
}

func TestSwipeReciprocalPositiveRaceCreatesOnePendingMatch(t *testing.T) {
	db, h := deckSetup(t)
	da := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)["context_id"].(string)
	dbb := call(t, h, "GET", "/v1/discovery", "bob", "", 200)["data"].(map[string]any)["context_id"].(string)
	if _, err := db.Exec(`INSERT INTO super_like_balances(user_id,available) VALUES($1,1)`, bob); err != nil {
		t.Fatal(err)
	}
	start := make(chan struct{})
	results := make(chan *httptest.ResponseRecorder, 2)
	for _, x := range []struct{ actor, key, body string }{{"alice", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", swipeBody(bob, da, "like")}, {"bob", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", swipeBody(alice, dbb, "super_like")}} {
		go func(actor, key, body string) {
			<-start
			r := httptest.NewRequest("POST", "/v1/discovery/actions", strings.NewReader(body))
			r.Header.Set("Authorization", "Bearer "+actor)
			r.Header.Set("Idempotency-Key", key)
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)
			results <- w
		}(x.actor, x.key, x.body)
	}
	close(start)
	matched := 0
	for range 2 {
		w := <-results
		if w.Code != 200 {
			t.Fatalf("reciprocal race %d %s", w.Code, w.Body.String())
		}
		var out map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
		m := out["data"].(map[string]any)["match"]
		if m != nil {
			matched++
			mm := m.(map[string]any)
			if mm["conversation_status"] != "pending" || mm["conversation_id"] != nil {
				t.Fatal("conversation falsely ready")
			}
		}
	}
	if matched != 1 {
		t.Fatalf("matched responses %d", matched)
	}
	for _, actor := range []string{"alice", "bob"} {
		u := call(t, h, "GET", "/v1/me/usage", actor, "", 200)["data"].(map[string]any)
		used := u["likes"].(map[string]any)["used"].(float64)
		want := float64(0)
		if actor == "alice" {
			want = 1
		}
		if used != want {
			t.Fatalf("%s likes debit%v want%v", actor, used, want)
		}
	}
}

func TestSwipeLastCreditRacesAndPassRemainsFree(t *testing.T) {
	for _, meter := range []string{"like", "super_like"} {
		t.Run(meter, func(t *testing.T) {
			db, h := deckSetup(t)
			third := "33333333-3333-4333-8333-333333333333"
			cloneDeckUser(t, db, third)
			d := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)["context_id"].(string)
			if meter == "like" {
				service, _ := limits.NewService(limits.Config{})
				tx, e := db.BeginTx(context.Background(), nil)
				if e != nil {
					t.Fatal(e)
				}
				u, e := service.UsageTx(context.Background(), tx, alice, time.Now())
				if e == nil {
					_, e = service.DebitTx(context.Background(), tx, limits.Request{OwnerID: alice, OperationID: "99999999-9999-4999-8999-999999999999", Meter: limits.Likes, Units: u.Likes.Available - 1, PayloadHash: "trusted-fixture-prior-consumption"}, time.Now())
				}
				if e != nil {
					tx.Rollback()
					t.Fatal(e)
				}
				if e = tx.Commit(); e != nil {
					t.Fatal(e)
				}
			} else {
				if _, e := db.Exec(`INSERT INTO super_like_balances(user_id,available) VALUES($1,1)`, alice); e != nil {
					t.Fatal(e)
				}
			}
			start := make(chan struct{})
			results := make(chan struct {
				target string
				w      *httptest.ResponseRecorder
			}, 2)
			for i, target := range []string{bob, third} {
				go func(i int, target string) {
					<-start
					r := httptest.NewRequest("POST", "/v1/discovery/actions", strings.NewReader(swipeBody(target, d, meter)))
					r.Header.Set("Authorization", "Bearer alice")
					r.Header.Set("Idempotency-Key", fmt.Sprintf("aaaaaaaa-aaaa-4aaa-8aaa-%012d", i))
					w := httptest.NewRecorder()
					h.ServeHTTP(w, r)
					results <- struct {
						target string
						w      *httptest.ResponseRecorder
					}{target, w}
				}(i, target)
			}
			close(start)
			success, limited := 0, 0
			loser := ""
			for range 2 {
				v := <-results
				switch v.w.Code {
				case 200:
					success++
				case 429:
					limited++
					loser = v.target
				default:
					t.Fatalf("credit race %d %s", v.w.Code, v.w.Body.String())
				}
			}
			if success != 1 || limited != 1 {
				t.Fatalf("credit race success%d limited%d", success, limited)
			}
			swipe(t, h, "alice", "cccccccc-cccc-4ccc-8ccc-cccccccccccc", swipeBody(loser, d, "pass"), 200)
			usage := call(t, h, "GET", "/v1/me/usage", "alice", "", 200)["data"].(map[string]any)
			if meter == "super_like" && usage["likes"].(map[string]any)["used"] != float64(0) {
				t.Fatal("superlike or pass consumed ordinary likes")
			}
		})
	}
}

func TestSwipeRejectsForeignStaleAndCurrentlyBlockedContexts(t *testing.T) {
	for _, reason := range []string{"foreign", "expired", "blocked", "restricted"} {
		t.Run(reason, func(t *testing.T) {
			db, h := deckSetup(t)
			actor := "alice"
			target := bob
			d := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)["context_id"].(string)
			status := 404
			switch reason {
			case "foreign":
				actor = "bob"
				target = alice
			case "expired":
				status = 409
				if _, e := db.Exec(`UPDATE deck_cache SET expires_at=now()-interval '1 second'`); e != nil {
					t.Fatal(e)
				}
			case "blocked":
				if _, e := db.Exec(`INSERT INTO user_blocks(blocker_id,blocked_id) VALUES($1,$2)`, bob, alice); e != nil {
					t.Fatal(e)
				}
			case "restricted":
				if _, e := db.Exec(`UPDATE accounts SET status='suspended' WHERE user_id=$1`, bob); e != nil {
					t.Fatal(e)
				}
			}
			v := swipe(t, h, actor, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", swipeBody(target, d, "like"), status)
			if status == 404 && v["error"].(map[string]any)["code"] != "NOT_FOUND" {
				t.Fatal("private restriction leaked")
			}
		})
	}
}
