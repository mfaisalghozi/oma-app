package discovery

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"oma/apps/api/internal/platform/httpapi"
	"time"
)

type CandidatePolicy struct {
	DefaultRadiusKM, MaxRadiusKM float64
	DefaultMinAge, DefaultMaxAge int
	LocationFreshDays, IdleDays  int
}

func (p CandidatePolicy) Validate() error {
	if math.IsNaN(p.DefaultRadiusKM) || math.IsInf(p.DefaultRadiusKM, 0) || math.IsNaN(p.MaxRadiusKM) || math.IsInf(p.MaxRadiusKM, 0) || p.DefaultRadiusKM <= 0 || p.MaxRadiusKM < p.DefaultRadiusKM || p.DefaultMinAge < 18 || p.DefaultMaxAge < p.DefaultMinAge || p.LocationFreshDays < 1 || p.IdleDays < 1 {
		return fmt.Errorf("invalid candidate policy")
	}
	return nil
}

type Candidate struct {
	ID, GenderID string
	Age          int
	DistanceKM   float64
	LastActiveAt time.Time
}

type CandidateQuery struct {
	DB     *sql.DB
	Policy CandidatePolicy
}

const candidateJoins = ` FROM profiles p JOIN accounts a ON a.user_id=p.user_id JOIN user_locations l ON l.user_id=p.user_id
 JOIN profiles vp ON vp.user_id=$1 JOIN user_locations vl ON vl.user_id=vp.user_id
 JOIN gender_options g ON g.id=p.gender_id JOIN gender_options vg ON vg.id=vp.gender_id
 JOIN show_me_options sm ON sm.id=p.show_me_option_id JOIN show_me_options vsm ON vsm.id=vp.show_me_option_id
 LEFT JOIN discovery_activity activity ON activity.user_id=p.user_id`

const candidateWhere = ` WHERE p.user_id<>$1 AND a.status='active' AND a.onboarding_completed_at IS NOT NULL AND required_consents_completed(p.user_id)
 AND EXISTS(SELECT 1 FROM photos ph WHERE ph.user_id=p.user_id AND ph.status='active')
 AND l.updated_at>now()-make_interval(days=>$5) AND vl.updated_at>now()-make_interval(days=>$5)
 AND COALESCE(activity.last_active_at,a.updated_at)>now()-make_interval(days=>$6)
 AND (vsm.code='everyone' OR vsm.code=g.code) AND (sm.code='everyone' OR sm.code=vg.code)
 AND date_part('year',age(p.birthdate))>=18 AND date_part('year',age(vp.birthdate))>=18
 AND date_part('year',age(p.birthdate)) BETWEEN COALESCE(vp.min_age,$7) AND COALESCE(vp.max_age,$8)
 AND date_part('year',age(vp.birthdate)) BETWEEN COALESCE(p.min_age,$7) AND COALESCE(p.max_age,$8)
 AND NOT EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=p.user_id) OR (b.blocker_id=p.user_id AND b.blocked_id=$1))
 AND NOT EXISTS(SELECT 1 FROM discovery_pair_exclusions e WHERE e.viewer_id=$1 AND e.candidate_id=p.user_id)`

func candidateFrom(extraJoins string, explicitRadius bool) string {
	radius := "COALESCE(NULLIF($2,0),vp.radius_km,$3)"
	if explicitRadius {
		radius = "COALESCE($2::double precision,$3::double precision)"
	}
	return candidateJoins + extraJoins + candidateWhere + " AND public.ST_DWithin(l.location,vl.location,LEAST(" + radius + ",$4::double precision)*1000)"
}

// Includes relation evidence that can change without a profile revision increment.
const evidenceSnapshotSQL = `jsonb_build_array(p.revision,vp.revision,date_part('year',age(p.birthdate)),l.location_version,vl.location_version,
 COALESCE((SELECT jsonb_agg(hobby_id ORDER BY hobby_id) FROM profile_hobbies WHERE user_id=p.user_id),'[]'::jsonb),
 COALESCE((SELECT jsonb_agg(looking_for_id ORDER BY looking_for_id) FROM profile_looking_for WHERE user_id=p.user_id),'[]'::jsonb))::text`

// Candidates returns an internal eligible pool, not a ranked deck or public projection.
// A zero radius uses the stored viewer preference, then the configured default.
func (q *CandidateQuery) Candidates(ctx context.Context, viewer string, radiusKM float64, limit int) ([]Candidate, error) {
	if err := q.validate(radiusKM, limit); err != nil {
		return nil, err
	}
	tx, err := q.DB.BeginTx(ctx, &sql.TxOptions{ReadOnly: true, Isolation: sql.LevelRepeatableRead})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	if err = check(ctx, tx, viewer); err != nil {
		return nil, err
	}
	out, err := q.candidates(ctx, tx, viewer, "", radiusKM, limit, false)
	if err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return out, nil
}

// VisibleTx lets a later action recheck the same hard filters in its transaction.
func (q *CandidateQuery) VisibleTx(ctx context.Context, tx *sql.Tx, viewer, target string, radiusKM float64) (bool, error) {
	if err := q.validate(radiusKM, 1); err != nil {
		return false, err
	}
	if !httpapi.ValidID(target) {
		return false, &httpapi.Error{Status: 400, Code: "INVALID_TARGET"}
	}
	if err := check(ctx, tx, viewer); err != nil {
		return false, err
	}
	got, err := q.candidates(ctx, tx, viewer, target, radiusKM, 1, false)
	return len(got) == 1, err
}
func (q *CandidateQuery) validate(radius float64, limit int) error {
	if err := q.Policy.Validate(); err != nil {
		return err
	}
	if math.IsNaN(radius) || math.IsInf(radius, 0) || radius < 0 {
		return &httpapi.Error{Status: 400, Code: "INVALID_RADIUS"}
	}
	if limit < 1 || limit > 300 {
		return &httpapi.Error{Status: 400, Code: "INVALID_LIMIT"}
	}
	return nil
}
func (q *CandidateQuery) candidates(ctx context.Context, tx *sql.Tx, viewer, target string, radius float64, limit int, explicitRadius bool) ([]Candidate, error) {
	p := q.Policy
	args := []any{viewer, radius, p.DefaultRadiusKM, p.MaxRadiusKM, p.LocationFreshDays, p.IdleDays, p.DefaultMinAge, p.DefaultMaxAge, limit}
	stmt := `SELECT p.user_id,p.gender_id,date_part('year',age(p.birthdate))::int,public.ST_Distance(l.location,vl.location)/1000,COALESCE(activity.last_active_at,a.updated_at)` + candidateFrom("", explicitRadius)
	if target != "" {
		stmt += ` AND p.user_id=$10`
		args = append(args, target)
	}
	rows, err := tx.QueryContext(ctx, stmt+` ORDER BY p.user_id LIMIT $9`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Candidate{}
	for rows.Next() {
		var c Candidate
		if err = rows.Scan(&c.ID, &c.GenderID, &c.Age, &c.DistanceKM, &c.LastActiveAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// VisibleRadiusTx rechecks an explicit Describe radius; zero means the same point.
func (q *CandidateQuery) VisibleRadiusTx(ctx context.Context, tx *sql.Tx, viewer, target string, radiusKM float64) (bool, error) {
	if err := q.validate(radiusKM, 1); err != nil {
		return false, err
	}
	if !httpapi.ValidID(target) {
		return false, &httpapi.Error{Status: 400, Code: "INVALID_TARGET"}
	}
	if err := check(ctx, tx, viewer); err != nil {
		return false, err
	}
	got, err := q.candidates(ctx, tx, viewer, target, radiusKM, 1, true)
	return len(got) == 1, err
}

func (q *CandidateQuery) EvidenceCurrentTx(ctx context.Context, tx *sql.Tx, viewer, target, snapshot string) (bool, error) {
	var current bool
	err := tx.QueryRowContext(ctx, `SELECT `+evidenceSnapshotSQL+`=$3 FROM profiles p JOIN user_locations l ON l.user_id=p.user_id JOIN profiles vp ON vp.user_id=$1 JOIN user_locations vl ON vl.user_id=vp.user_id WHERE p.user_id=$2`, viewer, target, snapshot).Scan(&current)
	if err == sql.ErrNoRows {
		return false, nil
	}
	return current, err
}
