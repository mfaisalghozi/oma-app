package describe

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"

	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
)

type SavedResult struct {
	Candidate discovery.Card `json:"candidate"`
	Ordinal   int            `json:"ordinal"`
	*Evaluation
	CriterionEvaluations []CriterionEvaluation `json:"criterion_evaluations"`
	ProfileUpdated       bool                  `json:"profile_updated"`
}

func (s *Service) Latest(w http.ResponseWriter, r *http.Request) {
	id, err := s.latestID(r.Context(), auth.UserID(r.Context()))
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	s.respond(w, r, auth.UserID(r.Context()), id, 200)
}
func (s *Service) latestID(ctx context.Context, owner string) (string, error) {
	var id string
	err := s.DB.QueryRowContext(ctx, `SELECT id FROM describe_searches WHERE owner_id=$1 AND state='succeeded' ORDER BY completed_at DESC,id DESC LIMIT 1`, owner).Scan(&id)
	if err == sql.ErrNoRows {
		return "", searchError(404, "NOT_FOUND")
	}
	return id, err
}
func (s *Service) Results(w http.ResponseWriter, r *http.Request) {
	owner := auth.UserID(r.Context())
	id := r.PathValue("search_id")
	if !httpapi.ValidID(id) {
		httpapi.Fail(w, 404, "NOT_FOUND")
		return
	}
	search, err := s.read(r.Context(), owner, id)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if search.State != "succeeded" {
		httpapi.Fail(w, 409, "SEARCH_NOT_SUCCESSFUL")
		return
	}
	var radius float64
	if err = s.DB.QueryRowContext(r.Context(), `SELECT effective_radius_km FROM describe_searches WHERE owner_id=$1 AND id=$2`, owner, id).Scan(&radius); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	rows, err := s.DB.QueryContext(r.Context(), `SELECT candidate_id,profile_revision,evaluation FROM describe_search_results WHERE search_id=$1 ORDER BY position`, id)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	ids := []string{}
	ordinals := map[string]int{}
	revs := map[string]int64{}
	evaluations := map[string]*Evaluation{}
	for rows.Next() {
		var candidate string
		var rev int64
		var raw []byte
		if err = rows.Scan(&candidate, &rev, &raw); err != nil {
			break
		}
		var e Evaluation
		if err = json.Unmarshal(raw, &e); err != nil {
			break
		}
		ids = append(ids, candidate)
		ordinals[candidate] = len(ids)
		revs[candidate] = rev
		evaluations[candidate] = &e
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	cards, err := s.Retriever.Profiles.ProjectRadius(r.Context(), owner, ids, radius)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	out := []SavedResult{}
	for _, card := range cards {
		stale := card.Revision != revs[card.ID]
		var e *Evaluation
		ce := []CriterionEvaluation{}
		if !stale {
			e = evaluations[card.ID]
			ce = e.Evaluations
		}
		out = append(out, SavedResult{Candidate: card, Ordinal: ordinals[card.ID], Evaluation: e, CriterionEvaluations: ce, ProfileUpdated: stale})
	}
	httpapi.Data(w, 200, map[string]any{"search_id": search.ID, "criteria": search.Criteria, "results": out, "parser_version": search.ParserVersion, "ranking_policy_version": search.RankingPolicyVersion, "policy_version": search.PolicyVersion})
}

// ContextTx derives the radius only from the owned successful search.
func (s *Service) ContextTx(ctx context.Context, tx *sql.Tx, viewer, target, id string) error {
	if !httpapi.ValidID(id) || !httpapi.ValidID(target) {
		return searchError(404, "NOT_FOUND")
	}
	var radius float64
	err := tx.QueryRowContext(ctx, `SELECT s.effective_radius_km FROM describe_searches s JOIN describe_search_results r ON r.search_id=s.id WHERE s.id=$1 AND s.owner_id=$2 AND s.state='succeeded' AND r.candidate_id=$3`, id, viewer, target).Scan(&radius)
	if err == sql.ErrNoRows {
		return searchError(404, "NOT_FOUND")
	}
	if err != nil {
		return err
	}
	visible, err := s.Retriever.Query.VisibleTx(ctx, tx, viewer, target, radius)
	if err != nil {
		return err
	}
	if !visible {
		return searchError(404, "NOT_FOUND")
	}
	return nil
}
