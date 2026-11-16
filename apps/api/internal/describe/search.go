package describe

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/riverqueue/river"
	"net/http"
	"time"

	"oma/apps/api/internal/limits"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
)

type Service struct {
	DB        *sql.DB
	Client    *river.Client[*sql.Tx]
	Parser    Parser
	Retriever Retriever
	Limits    *limits.Service
	Now       func() time.Time
}
type Search struct {
	ID                   string     `json:"search_id"`
	State                string     `json:"status"`
	Query                string     `json:"-"`
	Criteria             *Criteria  `json:"criteria"`
	ErrorCode            *string    `json:"error_code"`
	CreatedAt            time.Time  `json:"created_at"`
	CompletedAt          *time.Time `json:"completed_at,omitempty"`
	PollAfterSeconds     int        `json:"poll_after_seconds"`
	ParserVersion        string     `json:"parser_version"`
	RankingPolicyVersion string     `json:"ranking_policy_version"`
	PolicyVersion        string     `json:"policy_version"`
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}
func searchError(status int, code string) error { return &httpapi.Error{Status: status, Code: code} }
func (s *Service) configured() bool {
	return s.DB != nil && s.Parser.Provider != nil && s.Limits != nil && s.Retriever.Profiles != nil && s.Retriever.Query.DB == s.DB && s.Retriever.Query.Policy.Validate() == nil && s.Retriever.Profiles.Policy.Validate() == nil && s.Parser.Limits.valid()
}
func (s *Service) Create(w http.ResponseWriter, r *http.Request) {
	if !s.configured() || s.Client == nil {
		httpapi.Fail(w, 503, "DESCRIBE_NOT_CONFIGURED")
		return
	}
	var input struct {
		Query   string  `json:"query"`
		RetryOf *string `json:"retry_of,omitempty"`
	}
	if !httpapi.Decode(w, r, &input) {
		return
	}
	rawKey := r.Header.Get("Idempotency-Key")
	if len(rawKey) < 1 || len(rawKey) > 200 || !validText(input.Query, 500) {
		httpapi.Fail(w, 400, "INVALID_REQUEST")
		return
	}
	keySum := sha256.Sum256([]byte("describe:" + rawKey))
	keyHex := hex.EncodeToString(keySum[:16])
	key := keyHex[:8] + "-" + keyHex[8:12] + "-" + keyHex[12:16] + "-" + keyHex[16:20] + "-" + keyHex[20:]
	if input.RetryOf != nil && !httpapi.ValidID(*input.RetryOf) {
		httpapi.Fail(w, 400, "INVALID_REQUEST")
		return
	}
	canonical, _ := json.Marshal(input)
	hash := sha256.Sum256(canonical)
	fingerprint := hex.EncodeToString(hash[:])
	ctx := r.Context()
	owner := auth.UserID(ctx)
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	var lock string
	if err = tx.QueryRowContext(ctx, `SELECT user_id FROM accounts WHERE user_id=$1 AND status='active' AND onboarding_completed_at IS NOT NULL AND required_consents_completed(user_id) AND EXISTS(SELECT 1 FROM user_locations WHERE user_id=$1) FOR UPDATE`, owner).Scan(&lock); err != nil {
		if err == sql.ErrNoRows {
			httpapi.Fail(w, 403, "DISCOVERY_NOT_ELIGIBLE")
		} else {
			httpapi.HandleError(w, err)
		}
		return
	}
	var id, original string
	err = tx.QueryRowContext(ctx, `SELECT id,payload_hash FROM describe_searches WHERE owner_id=$1 AND request_id=$2`, owner, key).Scan(&id, &original)
	if err == nil {
		if original != fingerprint {
			httpapi.Fail(w, 409, "IDEMPOTENCY_CONFLICT")
			return
		}
		if err = tx.Commit(); err != nil {
			httpapi.HandleError(w, err)
			return
		}
		s.respond(w, r, owner, id, 200)
		return
	}
	if err != sql.ErrNoRows {
		httpapi.HandleError(w, err)
		return
	}
	if input.RetryOf != nil {
		var owned bool
		if err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM describe_searches WHERE id=$1 AND owner_id=$2 AND state='failed')`, *input.RetryOf, owner).Scan(&owned); err != nil {
			httpapi.HandleError(w, err)
			return
		}
		if !owned {
			httpapi.Fail(w, 400, "INVALID_RETRY")
			return
		}
	}
	var active bool
	if err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM describe_searches WHERE owner_id=$1 AND state IN ('pending','running'))`, owner).Scan(&active); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if active {
		httpapi.Fail(w, 409, "SEARCH_IN_PROGRESS")
		return
	}
	_, err = s.Limits.ReserveTx(ctx, tx, limits.Request{OwnerID: owner, OperationID: key, Meter: limits.Searches, Units: 1, PayloadHash: fingerprint}, s.now())
	if errors.Is(err, limits.ErrLimit) {
		httpapi.Fail(w, 429, "SEARCH_QUOTA_EXHAUSTED")
		return
	}
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = tx.QueryRowContext(ctx, `INSERT INTO describe_searches(owner_id,request_id,query,payload_hash,created_at,retry_of,parser_version,ranking_policy_version,policy_version) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`, owner, key, input.Query, fingerprint, s.now(), input.RetryOf, "v1", s.Retriever.Profiles.Policy.Ranking.Version, s.Retriever.Profiles.Policy.Version).Scan(&id); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if _, err = s.Client.InsertTx(ctx, tx, SearchArgs{SearchID: id}, nil); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	s.respond(w, r, owner, id, 202)
}
func (s *Service) read(ctx context.Context, owner, id string) (Search, error) {
	var v Search
	var raw []byte
	err := s.DB.QueryRowContext(ctx, `SELECT id,CASE WHEN state IN ('pending','running') THEN phase ELSE state END,query,criteria,error_code,created_at,completed_at,parser_version,ranking_policy_version,policy_version FROM describe_searches WHERE owner_id=$1 AND id=$2`, owner, id).Scan(&v.ID, &v.State, &v.Query, &raw, &v.ErrorCode, &v.CreatedAt, &v.CompletedAt, &v.ParserVersion, &v.RankingPolicyVersion, &v.PolicyVersion)
	if err == sql.ErrNoRows {
		return v, searchError(404, "NOT_FOUND")
	}
	if err != nil {
		return v, err
	}
	if v.State != "succeeded" && v.State != "failed" {
		v.PollAfterSeconds = 2
	}
	if raw != nil {
		err = json.Unmarshal(raw, &v.Criteria)
	}
	return v, err
}
func (s *Service) respond(w http.ResponseWriter, r *http.Request, owner, id string, status int) {
	v, err := s.read(r.Context(), owner, id)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, status, v)
}
func (s *Service) Status(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("search_id")
	if !httpapi.ValidID(id) {
		httpapi.Fail(w, 404, "NOT_FOUND")
		return
	}
	s.respond(w, r, auth.UserID(r.Context()), id, 200)
}
