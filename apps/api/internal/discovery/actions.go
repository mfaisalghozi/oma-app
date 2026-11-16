package discovery

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"sort"
	"strings"

	"oma/apps/api/internal/limits"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
)

type ActionRequest struct {
	TargetID    string `json:"target_id"`
	ContextID   string `json:"context_id"`
	ContextKind string `json:"context_kind"`
	Action      string `json:"action"`
}
type ActionResult struct {
	ID     string       `json:"action_id"`
	Action string       `json:"action"`
	Match  *MatchResult `json:"match"`
}
type MatchResult struct {
	ID                 string  `json:"id"`
	ConversationStatus string  `json:"conversation_status"`
	ConversationID     *string `json:"conversation_id"`
}

// Describe supplies its authoritative persisted-result validator when that domain is installed.
type ActionContextValidator func(context.Context, *sql.Tx, string, string, string) error

func (h *Handler) Action(w http.ResponseWriter, r *http.Request) {
	if err := h.configured(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	var req ActionRequest
	if !httpapi.Decode(w, r, &req) {
		return
	}
	key := strings.ToLower(r.Header.Get("Idempotency-Key"))
	req.TargetID = strings.ToLower(req.TargetID)
	req.ContextID = strings.ToLower(req.ContextID)
	if !httpapi.ValidID(key) || !httpapi.ValidID(req.TargetID) || !httpapi.ValidID(req.ContextID) || (req.Action != "pass" && req.Action != "like" && req.Action != "super_like") || (req.ContextKind != "regular_deck" && (req.ContextKind != "describe" || h.DescribeContext == nil)) || req.TargetID == auth.UserID(r.Context()) {
		httpapi.Fail(w, 400, "INVALID_ACTION")
		return
	}
	result, err := h.applyAction(r.Context(), auth.UserID(r.Context()), key, req)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 200, result)
}
func conflict() error { return &httpapi.Error{Status: 409, Code: "ACTION_CONFLICT"} }
func (h *Handler) applyAction(ctx context.Context, actor, key string, req ActionRequest) (ActionResult, error) {
	var out ActionResult
	tx, err := h.DB.BeginTx(ctx, nil)
	if err != nil {
		return out, err
	}
	defer tx.Rollback()
	// Sorted account locks serialize reciprocal decisions and preserve the quota/wallet lock order.
	ids := []string{actor, req.TargetID}
	sort.Strings(ids)
	for _, id := range ids {
		var found string
		if err = tx.QueryRowContext(ctx, `SELECT user_id FROM accounts WHERE user_id=$1 FOR UPDATE`, id).Scan(&found); err != nil {
			return out, rowsMissing(err)
		}
	}
	if err = check(ctx, tx, actor); err != nil {
		return out, err
	}
	raw, _ := json.Marshal(req)
	sum := sha256.Sum256(raw)
	hash := hex.EncodeToString(sum[:])
	var oldHash string
	var response []byte
	err = tx.QueryRowContext(ctx, `SELECT r.payload_hash,i.response FROM swipe_requests r JOIN profile_interactions i ON i.id=r.action_id WHERE r.actor_id=$1 AND r.idempotency_key=$2`, actor, key).Scan(&oldHash, &response)
	if err == nil {
		if oldHash != hash {
			return out, conflict()
		}
		err = json.Unmarshal(response, &out)
		return out, err
	}
	if err != sql.ErrNoRows {
		return out, err
	}
	var action string
	err = tx.QueryRowContext(ctx, `SELECT id,action,response FROM profile_interactions WHERE actor_id=$1 AND target_id=$2`, actor, req.TargetID).Scan(&out.ID, &action, &response)
	if err == nil {
		if action != req.Action {
			return out, conflict()
		}
		if _, err = tx.ExecContext(ctx, `INSERT INTO swipe_requests(actor_id,idempotency_key,payload_hash,action_id) VALUES($1,$2,$3,$4)`, actor, key, hash, out.ID); err != nil {
			return out, err
		}
		if err = json.Unmarshal(response, &out); err != nil {
			return out, err
		}
		return out, tx.Commit()
	}
	if err != sql.ErrNoRows {
		return out, err
	}
	if req.ContextKind == "regular_deck" {
		err = h.ContextTx(ctx, tx, actor, req.TargetID, req.ContextID)
	} else {
		err = h.DescribeContext(ctx, tx, actor, req.TargetID, req.ContextID)
	}
	if err != nil {
		return out, err
	}
	if req.Action == "like" {
		if h.Limits == nil {
			return out, &httpapi.Error{Status: 503, Code: "LIMITS_NOT_CONFIGURED"}
		}
		_, err = h.Limits.DebitTx(ctx, tx, limits.Request{OwnerID: actor, OperationID: key, Meter: limits.Likes, Units: 1, PayloadHash: hash}, h.now())
		if errors.Is(err, limits.ErrLimit) {
			return out, &httpapi.Error{Status: 429, Code: "LIKE_LIMIT_REACHED"}
		}
		if err != nil {
			return out, err
		}
	}
	if req.Action == "super_like" {
		res, e := tx.ExecContext(ctx, `UPDATE super_like_balances SET available=available-1 WHERE user_id=$1 AND available>0`, actor)
		if e != nil {
			return out, e
		}
		n, e := res.RowsAffected()
		if e != nil {
			return out, e
		}
		if n == 0 {
			return out, &httpapi.Error{Status: 429, Code: "SUPER_LIKE_BALANCE_EMPTY"}
		}
	}
	out.Action = req.Action
	if err = tx.QueryRowContext(ctx, `INSERT INTO profile_interactions(actor_id,target_id,action,context_kind,context_id,created_at) VALUES($1,$2,$3,$4,$5,$6) RETURNING id`, actor, req.TargetID, req.Action, req.ContextKind, req.ContextID, h.now()).Scan(&out.ID); err != nil {
		return out, err
	}
	if req.Action != "pass" {
		var reciprocal bool
		if err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM profile_interactions WHERE actor_id=$1 AND target_id=$2 AND action IN('like','super_like'))`, req.TargetID, actor).Scan(&reciprocal); err != nil {
			return out, err
		}
		if reciprocal {
			m := &MatchResult{}
			if err = tx.QueryRowContext(ctx, `INSERT INTO matches(user_low,user_high,created_at) VALUES($1,$2,$3) ON CONFLICT(user_low,user_high) DO UPDATE SET user_low=EXCLUDED.user_low RETURNING id,conversation_status,conversation_id`, ids[0], ids[1], h.now()).Scan(&m.ID, &m.ConversationStatus, &m.ConversationID); err != nil {
				return out, err
			}
			out.Match = m
		}
	}
	if _, err = tx.ExecContext(ctx, `INSERT INTO swipe_events(action_id,actor_id,target_id,action,segment_key,occurred_at) SELECT $1,$2,$3,$4,ag.code||':'||tg.code,$5 FROM profiles a JOIN gender_options ag ON ag.id=a.gender_id JOIN profiles t ON t.user_id=$3 JOIN gender_options tg ON tg.id=t.gender_id WHERE a.user_id=$2`, out.ID, actor, req.TargetID, req.Action, h.now()); err != nil {
		return out, err
	}
	response, err = json.Marshal(out)
	if err != nil {
		return out, err
	}
	if _, err = tx.ExecContext(ctx, `UPDATE profile_interactions SET response=$2 WHERE id=$1`, out.ID, string(response)); err != nil {
		return out, err
	}
	if _, err = tx.ExecContext(ctx, `INSERT INTO swipe_requests(actor_id,idempotency_key,payload_hash,action_id) VALUES($1,$2,$3,$4)`, actor, key, hash, out.ID); err != nil {
		return out, err
	}
	if req.ContextKind == "regular_deck" {
		if _, err = tx.ExecContext(ctx, `UPDATE deck_cache_cards SET action_id=$3 WHERE batch_id=$1 AND candidate_id=$2`, req.ContextID, req.TargetID, out.ID); err != nil {
			return out, err
		}
	}
	return out, tx.Commit()
}
