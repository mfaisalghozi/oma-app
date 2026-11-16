package discovery

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

type CandidateInput struct {
	ID, GenderID                                                                 string
	Likes, Passes, PriorMean, Percentile, ReplyRate, IdleDays, DistanceKM, Score float64
	Fresh, Priority                                                              bool
	PriorityAt                                                                   time.Time
	Bucket, Bypass                                                               string
}

type poolDB interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}

func (h *Handler) pool(ctx context.Context, tx poolDB, viewer string, radius, ring float64, cohort string, band, limit int) ([]CandidateInput, error) {
	p := h.Policy
	args := []any{viewer, radius, p.DefaultRadiusKM, p.MaxRadiusKM, p.LocationFreshDays, 14, p.DefaultMinAge, p.DefaultMaxAge, limit, ring, p.ShownDailyCap, p.PriorityTTLDays, p.PriorityCapBypass, p.Ranking.FallbackMean, h.now().In(time.FixedZone("WIB", 7*3600)).Format("2006-01-02")}
	priority := `EXISTS(SELECT 1 FROM discovery_incoming_priority ip WHERE ip.viewer_id=$1 AND ip.candidate_id=p.user_id AND ip.created_at>now()-make_interval(days=>$12) AND NOT EXISTS(SELECT 1 FROM deck_cache_cards dc JOIN deck_cache db ON db.id=dc.batch_id WHERE db.viewer_id=$1 AND dc.candidate_id=p.user_id AND dc.selection_bucket='priority' AND dc.delivered_at>=ip.created_at))`
	fresh := `p.created_at>now()-interval '72 hours' AND COALESCE((SELECT sum(shown_today) FROM candidate_daily_exposures ex WHERE ex.candidate_id=p.user_id),0)<30`
	from := strings.Replace(candidateFrom, " WHERE p.user_id", ` LEFT JOIN discovery_quality q ON q.candidate_id=p.user_id AND q.segment_key=vg.code||':'||g.code LEFT JOIN candidate_daily_exposures ex ON ex.candidate_id=p.user_id AND ex.bucket_date=$15::date WHERE p.user_id`, 1)
	from += ` AND (COALESCE(ex.shown_today,0)<$11 OR EXISTS(SELECT 1 FROM discovery_exposures e WHERE e.viewer_id=$1 AND e.candidate_id=p.user_id AND e.bucket_date=$15::date) OR ($13 AND ` + priority + `))`
	switch cohort {
	case "priority":
		from += ` AND ` + priority
	case "fresh":
		from += ` AND ` + fresh
	case "distance":
		from += fmt.Sprintf(` AND public.ST_Distance(l.location,vl.location)/1000>=$2*%f AND public.ST_Distance(l.location,vl.location)/1000<=$2*%f`, float64(band)/4, float64(band+1)/4)
	}
	sel := `SELECT p.user_id,p.gender_id,public.ST_Distance(l.location,vl.location)/1000,GREATEST(0,extract(epoch FROM now()-COALESCE(activity.last_active_at,a.updated_at))/86400),COALESCE(q.likes_w,0),COALESCE(q.passes_w,0),COALESCE(q.prior_mean,$14),COALESCE(q.percentile,0.5),COALESCE(q.reply_rate,0.75),` + fresh + `,` + priority + `,COALESCE((SELECT min(ip.created_at) FROM discovery_incoming_priority ip WHERE ip.viewer_id=$1 AND ip.candidate_id=p.user_id),'epoch'::timestamptz),COALESCE(ex.shown_today,0)`
	base := sel + from
	var stmt string
	if cohort == "priority" {
		stmt = base + ` AND $10::double precision>=0 ORDER BY (SELECT min(ip.created_at) FROM discovery_incoming_priority ip WHERE ip.viewer_id=$1 AND ip.candidate_id=p.user_id),p.user_id LIMIT $9`
	} else {
		stmt = `(` + base + ` AND p.random_key >=$10 ORDER BY p.random_key,p.user_id LIMIT $9) UNION ALL (` + base + ` AND p.random_key<$10 ORDER BY p.random_key,p.user_id LIMIT $9) LIMIT $9`
	}
	rows, err := tx.QueryContext(ctx, stmt, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []CandidateInput{}
	for rows.Next() {
		var c CandidateInput
		var count int
		if err = rows.Scan(&c.ID, &c.GenderID, &c.DistanceKM, &c.IdleDays, &c.Likes, &c.Passes, &c.PriorMean, &c.Percentile, &c.ReplyRate, &c.Fresh, &c.Priority, &c.PriorityAt, &count); err != nil {
			return nil, err
		}
		if count >= p.ShownDailyCap && c.Priority && p.PriorityCapBypass {
			c.Bypass = "incoming_super_like"
		}
		out = append(out, c)
	}
	return out, rows.Err()
}
