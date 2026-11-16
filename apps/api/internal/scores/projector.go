package scores

import (
	"context"
	"database/sql"
	"errors"
	"math"
	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/limits"
	"time"
)

type Service struct {
	db     *sql.DB
	policy discovery.RankingPolicy
}
type Result struct {
	Claimed int
	Busy    bool
}
type Quality struct {
	Likes, Passes, PriorMean, Percentile, ReplyRate float64
	CompletedMatches                                int64
}

func New(db *sql.DB, p discovery.RankingPolicy) (*Service, error) {
	if db == nil || p.Version == "" || p.LikeHalfLifeDays != 30 || p.MinSegmentDecisions <= 0 || math.IsNaN(p.MinSegmentDecisions) || math.IsInf(p.MinSegmentDecisions, 0) {
		return nil, errors.New("invalid score projection policy")
	}
	if _, err := discovery.Posterior(0, 0, p.FallbackMean, p); err != nil {
		return nil, err
	}
	return &Service{db: db, policy: p}, nil
}
func (s *Service) NightlyDue(ctx context.Context, now time.Time) (bool, error) {
	day, _ := limits.Bucket(now)
	var due bool
	err := s.db.QueryRowContext(ctx, `SELECT NOT EXISTS(SELECT 1 FROM score_rebuild_runs WHERE completed_at >= ($1::date::timestamp AT TIME ZONE 'Asia/Jakarta') AND policy_version=$2)`, day, s.policy.Version).Scan(&due)
	return due, err
}
func (s *Service) Lookup(ctx context.Context, candidate, segment string) (Quality, error) {
	var q Quality
	err := s.db.QueryRowContext(ctx, `SELECT likes_w,passes_w,prior_mean,percentile,reply_rate,completed_matches FROM discovery_quality WHERE candidate_id=$1 AND segment_key=$2`, candidate, segment).Scan(&q.Likes, &q.Passes, &q.PriorMean, &q.Percentile, &q.ReplyRate, &q.CompletedMatches)
	return q, err
}
func (s *Service) Project(ctx context.Context, now time.Time, nightly bool) (Result, error) {
	var result Result
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead})
	if err != nil {
		return result, err
	}
	defer tx.Rollback()
	// Relation identity isolates independent schemas while serializing every writer to these scores.
	var locked bool
	if err = tx.QueryRowContext(ctx, `SELECT pg_try_advisory_xact_lock(89217341, 'score_projection_receipts'::regclass::oid::int)`).Scan(&locked); err != nil {
		return result, err
	}
	if !locked {
		result.Busy = true
		return result, nil
	}
	claim := `CREATE TEMP TABLE score_claim ON COMMIT DROP AS SELECT e.id,e.actor_id,e.target_id,e.segment_key FROM swipe_events e WHERE e.occurred_at<=$1 AND NOT EXISTS(SELECT 1 FROM score_projection_receipts r WHERE r.event_id=e.id) ORDER BY e.id LIMIT 1000`
	if nightly {
		claim = `CREATE TEMP TABLE score_claim ON COMMIT DROP AS SELECT id,actor_id,target_id,segment_key FROM swipe_events WHERE occurred_at<=$1`
	}
	if _, err = tx.ExecContext(ctx, claim, now); err != nil {
		return result, err
	}
	if err = tx.QueryRowContext(ctx, `SELECT count(*) FROM score_claim`).Scan(&result.Claimed); err != nil {
		return result, err
	}
	if !nightly && result.Claimed == 0 {
		return result, tx.Commit()
	}
	weights := `INSERT INTO score_actor_weights(actor_id,weight,computed_at,policy_version)
 SELECT a.user_id,CASE WHEN a.status<>'active' OR a.created_at>$1::timestamptz-interval '3 days' OR a.phone_verified_at IS NULL OR a.phone_verified_at>$1 THEN 0 WHEN COALESCE(x.rate,0)>0.8 THEN 0.25 ELSE 1 END,$1,$2
 FROM accounts a LEFT JOIN LATERAL(SELECT avg((action<>'pass')::int) rate FROM(SELECT action FROM swipe_events e WHERE e.actor_id=a.user_id AND e.occurred_at<=$1 ORDER BY occurred_at DESC,id DESC LIMIT 100) recent)x ON true`
	if !nightly {
		weights += ` WHERE a.user_id IN(SELECT actor_id FROM score_claim)`
	}
	weights += ` ON CONFLICT(actor_id) DO UPDATE SET weight=EXCLUDED.weight,computed_at=EXCLUDED.computed_at,policy_version=EXCLUDED.policy_version`
	if _, err = tx.ExecContext(ctx, weights, now, s.policy.Version); err != nil {
		return result, err
	}
	if nightly {
		if _, err = tx.ExecContext(ctx, `DELETE FROM score_segment_priors; DELETE FROM score_values; DELETE FROM score_reply_stats`); err != nil {
			return result, err
		}
		if _, err = tx.ExecContext(ctx, `INSERT INTO score_segment_priors(segment_key,mean,support,policy_version,computed_at)
 SELECT e.segment_key,CASE WHEN sum(w.weight*power(0.5,extract(epoch FROM($1::timestamptz-e.occurred_at))/86400/30))>=$3 THEN greatest(0.000001,least(0.999999,sum((e.action<>'pass')::int*w.weight*power(0.5,extract(epoch FROM($1::timestamptz-e.occurred_at))/86400/30))/NULLIF(sum(w.weight*power(0.5,extract(epoch FROM($1::timestamptz-e.occurred_at))/86400/30)),0))) ELSE $2 END,sum(w.weight*power(0.5,extract(epoch FROM($1::timestamptz-e.occurred_at))/86400/30)),$4,$1
 FROM swipe_events e JOIN score_actor_weights w ON w.actor_id=e.actor_id WHERE e.occurred_at BETWEEN $1::timestamptz-interval '120 days' AND $1 GROUP BY e.segment_key`, now, s.policy.FallbackMean, s.policy.MinSegmentDecisions, s.policy.Version); err != nil {
			return result, err
		}
		if _, err = tx.ExecContext(ctx, `INSERT INTO score_reply_stats(user_id,opportunities,replies,computed_at) SELECT respondent_id,count(*),count(*) FILTER(WHERE first_reply_at<=opened_at+interval '48 hours'),$1 FROM score_reply_windows WHERE opened_at<=$1::timestamptz-interval '48 hours' GROUP BY respondent_id`, now); err != nil {
			return result, err
		}
	}
	work := `CREATE TEMP TABLE score_work ON COMMIT DROP AS SELECT DISTINCT target_id candidate_id,segment_key FROM score_claim`
	if nightly {
		work = `CREATE TEMP TABLE score_work ON COMMIT DROP AS SELECT p.user_id candidate_id,vg.code||':'||g.code segment_key FROM profiles p JOIN gender_options g ON g.id=p.gender_id CROSS JOIN gender_options vg UNION SELECT DISTINCT target_id,segment_key FROM swipe_events`
	}
	if _, err = tx.ExecContext(ctx, work); err != nil {
		return result, err
	}
	if _, err = tx.ExecContext(ctx, `WITH sums AS(
 SELECT c.candidate_id,c.segment_key,COALESCE(sum((e.action<>'pass')::int*COALESCE(w.weight,0)*power(0.5,extract(epoch FROM($1::timestamptz-e.occurred_at))/86400/30)),0) l,COALESCE(sum((e.action='pass')::int*COALESCE(w.weight,0)*power(0.5,extract(epoch FROM($1::timestamptz-e.occurred_at))/86400/30)),0) p
 FROM score_work c LEFT JOIN swipe_events e ON e.target_id=c.candidate_id AND e.segment_key=c.segment_key AND e.occurred_at BETWEEN $1::timestamptz-interval '120 days' AND $1 LEFT JOIN score_actor_weights w ON w.actor_id=e.actor_id GROUP BY c.candidate_id,c.segment_key
 ),post AS(SELECT s.*,CASE WHEN sp.support>=$3 AND sp.policy_version=$5 THEN sp.mean ELSE $2 END mu FROM sums s LEFT JOIN score_segment_priors sp USING(segment_key))
 INSERT INTO score_values(candidate_id,segment_key,likes_w,passes_w,prior_mean,theta_mean,percentile,policy_version,computed_at) SELECT candidate_id,segment_key,l,p,mu,(l+$4*mu)/(l+p+$4),0.5,$5,$1 FROM post
 ON CONFLICT(candidate_id,segment_key) DO UPDATE SET likes_w=EXCLUDED.likes_w,passes_w=EXCLUDED.passes_w,prior_mean=EXCLUDED.prior_mean,theta_mean=EXCLUDED.theta_mean,policy_version=EXCLUDED.policy_version,computed_at=EXCLUDED.computed_at`, now, s.policy.FallbackMean, s.policy.MinSegmentDecisions, s.policy.PriorStrength, s.policy.Version); err != nil {
		return result, err
	}
	if nightly {
		if _, err = tx.ExecContext(ctx, `WITH ranked AS(SELECT candidate_id,segment_key,CASE WHEN count(*) OVER(PARTITION BY segment_key)=1 THEN 0.5 ELSE percent_rank() OVER(PARTITION BY segment_key ORDER BY theta_mean) END pct FROM score_values) UPDATE score_values s SET percentile=r.pct FROM ranked r WHERE s.candidate_id=r.candidate_id AND s.segment_key=r.segment_key`); err != nil {
			return result, err
		}
	}
	if _, err = tx.ExecContext(ctx, `INSERT INTO score_projection_receipts(event_id,projected_at,policy_version) SELECT id,$1,$2 FROM score_claim ON CONFLICT(event_id) DO NOTHING`, now, s.policy.Version); err != nil {
		return result, err
	}
	if nightly {
		if _, err = tx.ExecContext(ctx, `INSERT INTO score_rebuild_runs(completed_at,policy_version) VALUES($1,$2)`, now, s.policy.Version); err != nil {
			return result, err
		}
	}
	return result, tx.Commit()
}
