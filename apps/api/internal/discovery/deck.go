package discovery

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/binary"
	"errors"
	"math/rand/v2"
	"net/http"
	"oma/apps/api/internal/account"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"sort"
	"strconv"
	"time"
)

type batch struct {
	ID         string
	Expires    time.Time
	Generation int64
}

func (h *Handler) configured() error {
	if h.Policy.Validate() != nil {
		return &httpapi.Error{Status: 503, Code: "DISCOVERY_NOT_CONFIGURED"}
	}
	return nil
}
func (h *Handler) Deck(w http.ResponseWriter, r *http.Request) {
	if err := h.configured(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	limit := 20
	if s := r.URL.Query().Get("limit"); s != "" {
		v, e := strconv.Atoi(s)
		if e != nil || v < 1 || v > 20 {
			httpapi.Fail(w, 400, "INVALID_LIMIT")
			return
		}
		limit = v
	}
	viewer := auth.UserID(r.Context())
	cur := r.URL.Query().Get("cursor")
	if cur != "" && !httpapi.ValidID(cur) {
		httpapi.Fail(w, 400, "INVALID_CURSOR")
		return
	}
	b, pos, err := h.ensureBatch(r.Context(), viewer, cur)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	rows, err := h.DB.QueryContext(r.Context(), `SELECT candidate_id,position FROM deck_cache_cards WHERE batch_id=$1 AND action_id IS NULL AND position>$2 ORDER BY position LIMIT $3`, b.ID, pos, limit)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	ids := []string{}
	last := pos
	for rows.Next() {
		var id string
		if err = rows.Scan(&id, &last); err != nil {
			break
		}
		ids = append(ids, id)
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	cards, err := h.Project(r.Context(), viewer, ids)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	var next *string
	var more bool
	if err = h.DB.QueryRowContext(r.Context(), `SELECT EXISTS(SELECT 1 FROM deck_cache_cards WHERE batch_id=$1 AND action_id IS NULL AND position>$2)`, b.ID, last).Scan(&more); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if more {
		var token string
		err = h.DB.QueryRowContext(r.Context(), `INSERT INTO deck_cursors(batch_id,position) VALUES($1,$2) ON CONFLICT(batch_id,position) DO UPDATE SET position=EXCLUDED.position RETURNING id`, b.ID, last).Scan(&token)
		if err != nil {
			httpapi.HandleError(w, err)
			return
		}
		next = &token
	}
	if r.Method != http.MethodHead {
		cards, err = h.deliver(r.Context(), viewer, b.ID, cards)
		if err != nil {
			httpapi.HandleError(w, err)
			return
		}
	}
	var reason *string
	if len(cards) == 0 {
		x := "candidate_pool_exhausted"
		reason = &x
	}
	httpapi.Data(w, 200, map[string]any{"context_id": b.ID, "cards": cards, "next_cursor": next, "deck_expires_at": b.Expires, "end_reason": reason})
}
func (h *Handler) ensureBatch(ctx context.Context, viewer, token string) (batch, int, error) {
	var b batch
	tx, err := h.DB.BeginTx(ctx, nil)
	if err != nil {
		return b, 0, err
	}
	defer tx.Rollback()
	if err = lockDeckViewer(ctx, tx, viewer); err != nil {
		return b, 0, err
	}
	if err = check(ctx, tx, viewer); err != nil {
		return b, 0, err
	}
	if _, err = tx.ExecContext(ctx, `INSERT INTO discovery_activity(user_id,last_active_at) VALUES($1,$2) ON CONFLICT(user_id) DO UPDATE SET last_active_at=EXCLUDED.last_active_at`, viewer, h.now()); err != nil {
		return b, 0, err
	}
	var lv, pv int64
	var radius float64
	if err = tx.QueryRowContext(ctx, `SELECT l.location_version,p.preference_revision,LEAST(COALESCE(p.radius_km,$2),$3) FROM profiles p JOIN user_locations l ON l.user_id=p.user_id WHERE p.user_id=$1`, viewer, h.Policy.DefaultRadiusKM, h.Policy.MaxRadiusKM).Scan(&lv, &pv, &radius); err != nil {
		return b, 0, err
	}
	var valid bool
	err = tx.QueryRowContext(ctx, `SELECT d.id,d.expires_at,d.generation,d.expires_at>$2 AND d.preference_revision=$3 AND d.policy_version=$4 AND d.ranking_version=$5 AND public.ST_Distance(d.location,l.location)<$6 AND d.exposure_bucket_date=$7::date FROM deck_cache d JOIN user_locations l ON l.user_id=d.viewer_id WHERE d.viewer_id=$1 AND d.status='active'`, viewer, h.now(), pv, h.policyVersion(), h.Policy.Ranking.Version, h.Policy.MaterialMovementMeters, h.bucketDay()).Scan(&b.ID, &b.Expires, &b.Generation, &valid)
	if err != nil && err != sql.ErrNoRows {
		return b, 0, err
	}
	pos := 0
	if token != "" {
		var batchID string
		if err = tx.QueryRowContext(ctx, `SELECT c.batch_id,c.position FROM deck_cursors c JOIN deck_cache d ON d.id=c.batch_id WHERE c.id=$1 AND d.viewer_id=$2`, token, viewer).Scan(&batchID, &pos); err == sql.ErrNoRows {
			return b, 0, &httpapi.Error{Status: 400, Code: "INVALID_CURSOR"}
		} else if err != nil {
			return b, 0, err
		}
		if batchID != b.ID || !valid {
			return b, 0, stale()
		}
	}
	if valid {
		var undecided, hasCards bool
		if err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM deck_cache_cards WHERE batch_id=$1 AND action_id IS NULL),EXISTS(SELECT 1 FROM deck_cache_cards WHERE batch_id=$1)`, b.ID).Scan(&undecided, &hasCards); err != nil {
			return b, 0, err
		}
		if undecided || !hasCards || token != "" {
			return b, pos, tx.Commit()
		}
	}
	if _, err = tx.ExecContext(ctx, `UPDATE deck_cache SET status='expired' WHERE viewer_id=$1 AND status='active'`, viewer); err != nil {
		return b, 0, err
	}
	if err = tx.QueryRowContext(ctx, `SELECT COALESCE(max(generation),0)+1 FROM deck_cache WHERE viewer_id=$1`, viewer).Scan(&b.Generation); err != nil {
		return b, 0, err
	}
	seed := sha256.Sum256([]byte(viewer + strconv.FormatInt(b.Generation, 10)))
	ring := float64(binary.BigEndian.Uint64(seed[:8])>>11) / (1 << 53)
	pool := []CandidateInput{}
	seen := map[string]bool{}
	appendPool := func(part []CandidateInput) {
		for _, c := range part {
			if !seen[c.ID] && len(pool) < 300 {
				seen[c.ID] = true
				pool = append(pool, c)
			}
		}
	}
	type cohort struct {
		kind        string
		band, quota int
	}
	cohorts := []cohort{{"priority", 0, h.Policy.PriorityCap}, {"fresh", 0, h.Policy.FreshCap}}
	remain := 300 - h.Policy.PriorityCap - h.Policy.FreshCap
	for i, v := range h.Policy.DistanceBandPercent {
		cohorts = append(cohorts, cohort{"distance", i, remain * v / 100})
	}
	for _, co := range cohorts {
		if co.quota == 0 {
			continue
		}
		part, e := h.pool(ctx, tx, viewer, radius, ring, co.kind, co.band, co.quota)
		if e != nil {
			return b, 0, e
		}
		appendPool(part)
	}
	if len(pool) < 300 {
		part, e := h.pool(ctx, tx, viewer, radius, ring, "", 0, 300)
		if e != nil {
			return b, 0, e
		}
		appendPool(part)
	}
	rng := rand.New(rand.NewPCG(binary.BigEndian.Uint64(seed[:8]), binary.BigEndian.Uint64(seed[8:16])))
	for i := range pool {
		p, e := Posterior(pool[i].Likes, pool[i].Passes, pool[i].PriorMean, h.Policy.Ranking)
		if e != nil {
			return b, 0, e
		}
		a, bb := gamma(rng, p.Alpha), gamma(rng, p.Beta)
		pool[i].Score, e = QualityScore(a/(a+bb), pool[i].ReplyRate, pool[i].IdleDays, pool[i].DistanceKM, radius, h.Policy.Ranking)
		if e != nil {
			return b, 0, e
		}
	}
	pro := h.IsPro != nil && h.IsPro(viewer)
	if h.Limits != nil {
		u, e := h.Limits.UsageTx(ctx, tx, viewer, h.now())
		if e != nil {
			return b, 0, e
		}
		pro = u.PRO
	}
	deck := AssembleDeck(pool, h.Policy, pro)
	b.Expires = h.now().Add(30 * time.Minute)
	if err = tx.QueryRowContext(ctx, `INSERT INTO deck_cache(viewer_id,generation,location_version,preference_revision,location,policy_version,ranking_version,expires_at,exposure_bucket_date) SELECT $1,$2,$3,$4,location,$5,$6,$7,$8 FROM user_locations WHERE user_id=$1 RETURNING id`, viewer, b.Generation, lv, pv, h.policyVersion(), h.Policy.Ranking.Version, b.Expires, h.bucketDay()).Scan(&b.ID); err != nil {
		return b, 0, err
	}
	for i, c := range deck {
		if _, err = tx.ExecContext(ctx, `INSERT INTO deck_cache_cards(batch_id,candidate_id,position,selection_bucket,bypass_reason) VALUES($1,$2,$3,$4,NULLIF($5,''))`, b.ID, c.ID, i+1, c.Bucket, c.Bypass); err != nil {
			return b, 0, err
		}
	}
	return b, 0, tx.Commit()
}

func (h *Handler) ContextTx(ctx context.Context, tx *sql.Tx, viewer, target, contextID string) error {
	return h.contextTx(ctx, tx, viewer, target, contextID, true)
}
func (h *Handler) contextTx(ctx context.Context, tx *sql.Tx, viewer, target, contextID string, requireDelivered bool) error {
	if !httpapi.ValidID(contextID) || !httpapi.ValidID(target) {
		return unavailable()
	}
	var valid bool
	err := tx.QueryRowContext(ctx, `SELECT d.status='active' AND d.expires_at>$4 AND d.preference_revision=p.preference_revision AND d.policy_version=$5 AND d.ranking_version=$6 AND public.ST_Distance(d.location,l.location)<$7 AND c.action_id IS NULL AND (NOT $8 OR c.delivered_at IS NOT NULL) AND d.exposure_bucket_date=$9::date FROM deck_cache d JOIN deck_cache_cards c ON c.batch_id=d.id JOIN profiles p ON p.user_id=d.viewer_id JOIN user_locations l ON l.user_id=d.viewer_id WHERE d.id=$1 AND d.viewer_id=$2 AND c.candidate_id=$3`, contextID, viewer, target, h.now(), h.policyVersion(), h.Policy.Ranking.Version, h.Policy.MaterialMovementMeters, requireDelivered, h.bucketDay()).Scan(&valid)
	if err == sql.ErrNoRows {
		return unavailable()
	}
	if err != nil {
		return err
	}
	if !valid {
		return stale()
	}
	q := CandidateQuery{h.DB, h.Policy.candidatePolicy()}
	visible, err := q.VisibleTx(ctx, tx, viewer, target, 0)
	if err != nil {
		return err
	}
	if !visible {
		return unavailable()
	}
	return nil
}
func (h *Handler) Candidate(w http.ResponseWriter, r *http.Request) {
	if err := h.configured(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	ctx := r.Context()
	viewer := auth.UserID(ctx)
	id := r.PathValue("candidate_id")
	tx, err := h.DB.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	if err = h.ContextTx(ctx, tx, viewer, id, r.URL.Query().Get("context_id")); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	cards, err := h.Project(ctx, viewer, []string{id})
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if len(cards) != 1 {
		httpapi.HandleError(w, unavailable())
		return
	}
	httpapi.Data(w, 200, cards[0])
}

func (h *Handler) deliver(ctx context.Context, viewer, batchID string, cards []Card) ([]Card, error) {
	tx, err := h.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	if err = lockDeckViewer(ctx, tx, viewer); err != nil {
		return nil, err
	}
	// Lock candidate daily rows in a single order so overlapping viewers cannot deadlock.
	ordered := append([]Card(nil), cards...)
	sort.Slice(ordered, func(i, j int) bool { return ordered[i].ID < ordered[j].ID })
	day := h.now().In(time.FixedZone("WIB", 7*3600)).Format("2006-01-02")
	allowed := map[string]bool{}
	for _, c := range ordered {
		if err = h.contextTx(ctx, tx, viewer, c.ID, batchID, false); err != nil {
			var pe *httpapi.Error
			if errors.As(err, &pe) {
				continue
			}
			return nil, err
		}
		if _, err = tx.ExecContext(ctx, `INSERT INTO candidate_daily_exposures(candidate_id,bucket_date) VALUES($1,$2) ON CONFLICT DO NOTHING`, c.ID, day); err != nil {
			return nil, err
		}
		var count int
		if err = tx.QueryRowContext(ctx, `SELECT shown_today FROM candidate_daily_exposures WHERE candidate_id=$1 AND bucket_date=$2 FOR UPDATE`, c.ID, day).Scan(&count); err != nil {
			return nil, err
		}
		var exposed, bypass bool
		if err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM discovery_exposures WHERE viewer_id=$1 AND candidate_id=$2 AND bucket_date=$3),$5 AND EXISTS(SELECT 1 FROM deck_cache_cards dc JOIN discovery_incoming_priority ip ON ip.viewer_id=$1 AND ip.candidate_id=dc.candidate_id WHERE dc.batch_id=$4 AND dc.candidate_id=$2 AND dc.selection_bucket='priority' AND ip.created_at>$6::timestamptz-make_interval(days=>$7))`, viewer, c.ID, day, batchID, h.Policy.PriorityCapBypass, h.now(), h.Policy.PriorityTTLDays).Scan(&exposed, &bypass); err != nil {
			return nil, err
		}
		if !exposed && count >= h.Policy.ShownDailyCap && !bypass {
			continue
		}
		if !exposed {
			res, e := tx.ExecContext(ctx, `INSERT INTO discovery_exposures(viewer_id,candidate_id,bucket_date,delivered_at) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING`, viewer, c.ID, day, h.now())
			if e != nil {
				return nil, e
			}
			n, e := res.RowsAffected()
			if e != nil {
				return nil, e
			}
			if n == 1 {
				if _, err = tx.ExecContext(ctx, `UPDATE candidate_daily_exposures SET shown_today=shown_today+1 WHERE candidate_id=$1 AND bucket_date=$2`, c.ID, day); err != nil {
					return nil, err
				}
			}
		}
		if _, err = tx.ExecContext(ctx, `UPDATE deck_cache_cards SET delivered_at=COALESCE(delivered_at,$3) WHERE batch_id=$1 AND candidate_id=$2`, batchID, c.ID, h.now()); err != nil {
			return nil, err
		}
		allowed[c.ID] = true
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	out := []Card{}
	for _, c := range cards {
		if allowed[c.ID] {
			out = append(out, c)
		}
	}
	return out, nil
}

func (h *Handler) bucketDay() string {
	return h.now().In(time.FixedZone("WIB", 7*3600)).Format("2006-01-02")
}

func lockDeckViewer(ctx context.Context, tx *sql.Tx, viewer string) error {
	var status string
	err := tx.QueryRowContext(ctx, `SELECT status FROM accounts WHERE user_id=$1 FOR NO KEY UPDATE`, viewer).Scan(&status)
	if err == sql.ErrNoRows {
		return &httpapi.Error{Status: 403, Code: "ACCOUNT_NOT_INITIALIZED"}
	}
	if err != nil {
		return err
	}
	return account.StatusError(status)
}

func (h *Handler) policyVersion() string { return h.Policy.Version + "/" + h.Policy.DeckVersion }
