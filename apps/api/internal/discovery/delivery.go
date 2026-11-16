package discovery

import (
	"context"
	"database/sql"
	"sort"
)

// DeliverRadiusTx shares first-delivery accounting across saved searches and decks.
func (h *Handler) DeliverRadiusTx(ctx context.Context, tx *sql.Tx, viewer string, cards []Card, radius float64) ([]Card, error) {
	ids := []string{viewer}
	seen := map[string]bool{viewer: true}
	for _, card := range cards {
		if !seen[card.ID] {
			ids = append(ids, card.ID)
			seen[card.ID] = true
		}
	}
	sort.Strings(ids)
	for _, id := range ids {
		var found string
		err := tx.QueryRowContext(ctx, `SELECT user_id FROM accounts WHERE user_id=$1 FOR UPDATE`, id).Scan(&found)
		if err != nil && !(err == sql.ErrNoRows && id != viewer) {
			return nil, err
		}
	}
	if err := check(ctx, tx, viewer); err != nil {
		return nil, err
	}
	query := CandidateQuery{DB: h.DB, Policy: h.Policy.candidatePolicy()}
	ordered := append([]Card(nil), cards...)
	sort.Slice(ordered, func(i, j int) bool { return ordered[i].ID < ordered[j].ID })
	allowed := map[string]bool{}
	day := h.bucketDay()
	for _, card := range ordered {
		visible, err := query.VisibleRadiusTx(ctx, tx, viewer, card.ID, radius)
		if err != nil {
			return nil, err
		}
		if !visible {
			continue
		}
		current, err := query.EvidenceCurrentTx(ctx, tx, viewer, card.ID, card.EvidenceSnapshot)
		if err != nil {
			return nil, err
		}
		if !current {
			continue
		}
		if _, err = tx.ExecContext(ctx, `INSERT INTO candidate_daily_exposures(candidate_id,bucket_date) VALUES($1,$2) ON CONFLICT DO NOTHING`, card.ID, day); err != nil {
			return nil, err
		}
		var count int
		if err = tx.QueryRowContext(ctx, `SELECT shown_today FROM candidate_daily_exposures WHERE candidate_id=$1 AND bucket_date=$2 FOR UPDATE`, card.ID, day).Scan(&count); err != nil {
			return nil, err
		}
		var exposed bool
		if err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM discovery_exposures WHERE viewer_id=$1 AND candidate_id=$2 AND bucket_date=$3)`, viewer, card.ID, day).Scan(&exposed); err != nil {
			return nil, err
		}
		if !exposed && count >= h.Policy.ShownDailyCap {
			continue
		}
		if !exposed {
			result, e := tx.ExecContext(ctx, `INSERT INTO discovery_exposures(viewer_id,candidate_id,bucket_date,delivered_at) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING`, viewer, card.ID, day, h.now())
			if e != nil {
				return nil, e
			}
			n, e := result.RowsAffected()
			if e != nil {
				return nil, e
			}
			if n == 1 {
				if _, e = tx.ExecContext(ctx, `UPDATE candidate_daily_exposures SET shown_today=shown_today+1 WHERE candidate_id=$1 AND bucket_date=$2`, card.ID, day); e != nil {
					return nil, e
				}
			}
		}
		allowed[card.ID] = true
	}
	out := []Card{}
	for _, card := range cards {
		if allowed[card.ID] {
			out = append(out, card)
		}
	}
	return out, nil
}
