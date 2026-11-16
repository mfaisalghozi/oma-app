package discovery

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"math"
	"oma/apps/api/internal/limits"
	"strings"
	"time"
)

// CandidateClause accepts validated profile facts, never executable predicates.
type CandidateClause struct {
	Field, Operator, Text, CatalogID string
	Number                           *float64
}
type FilteredCandidate struct {
	Candidate
	Snapshot            string `json:"-"`
	HeightCM            int
	Bio, Ambition       string
	Quality             float64
	ReplyRate, IdleDays float64
	Catalog             map[string][]string
}

type FilteredPolicy struct {
	Ranking       RankingPolicy
	ShownDailyCap int
	Now           time.Time
}

// Filtered ranks the fully eligible universe before limiting each exact/close tier.
func (q *CandidateQuery) Filtered(ctx context.Context, viewer string, radiusKM float64, must, nice []CandidateClause, policy FilteredPolicy) ([]FilteredCandidate, error) {
	if err := q.validate(radiusKM, 10); err != nil {
		return nil, err
	}
	if len(must)+len(nice) == 0 || len(must)+len(nice) > 24 {
		return nil, fmt.Errorf("invalid candidate clauses")
	}

	if policy.ShownDailyCap < 1 || policy.Now.IsZero() {
		return nil, fmt.Errorf("invalid filtered policy")
	}
	if _, err := QualityScore(.5, .75, 0, 0, 1, policy.Ranking); err != nil {
		return nil, err
	}
	p := q.Policy
	args := []any{viewer, radiusKM, p.DefaultRadiusKM, p.MaxRadiusKM, p.LocationFreshDays, p.IdleDays, p.DefaultMinAge, p.DefaultMaxAge}
	bind := func(value any) string { args = append(args, value); return fmt.Sprintf("$%d", len(args)) }
	exact, close, niceMatches := []string{}, []string{}, []string{}
	for group, clauses := range [][]CandidateClause{must, nice} {
		for _, c := range clauses {
			expression, relaxed, err := clauseSQL(c, bind, group == 0)
			if err != nil {
				return nil, err
			}
			if group == 0 {
				exact = append(exact, expression)
				close = append(close, relaxed)
			} else {
				niceMatches = append(niceMatches, "CASE WHEN "+expression+" THEN 1.0 ELSE 0.0 END")
			}
		}
	}
	and := func(v []string) string {
		if len(v) == 0 {
			return "TRUE"
		}
		return "(" + strings.Join(v, " AND ") + ")"
	}
	relevance := "1.0"
	if len(niceMatches) > 0 {
		relevance = "(" + strings.Join(niceMatches, "+") + ")/" + fmt.Sprint(len(niceMatches))
	}

	floor, half, at := bind(policy.Ranking.ReplyFloor), bind(policy.Ranking.RecencyHalfLifeDays), bind(policy.Now)
	idle := "GREATEST(0,extract(epoch FROM(" + at + "::timestamptz-COALESCE(activity.last_active_at,a.updated_at)))/86400)"
	quality := "COALESCE(q.percentile,0.5)*(" + floor + "::double precision+(1-" + floor + ")*COALESCE(q.reply_rate,0.75))*power(0.5," + idle + "/" + half + "::double precision)"

	day, _ := limits.Bucket(policy.Now)
	bucket, cap := bind(day), bind(policy.ShownDailyCap)
	from := candidateFrom(` LEFT JOIN discovery_quality q ON q.candidate_id=p.user_id AND q.segment_key=vg.code||':'||g.code LEFT JOIN candidate_daily_exposures ex ON ex.candidate_id=p.user_id AND ex.bucket_date=`+bucket+`::date`, true)
	from += ` AND (COALESCE(ex.shown_today,0)<` + cap + ` OR EXISTS(SELECT 1 FROM discovery_exposures e WHERE e.viewer_id=$1 AND e.candidate_id=p.user_id AND e.bucket_date=` + bucket + `::date))`

	query := `WITH eligible AS (SELECT ` + evidenceSnapshotSQL + ` AS snapshot,p.user_id,p.gender_id,date_part('year',age(p.birthdate))::int AS age,public.ST_Distance(l.location,vl.location)/1000 AS distance,COALESCE(activity.last_active_at,a.updated_at) AS active,p.height_cm,p.bio,COALESCE(p.ambition,'') AS ambition,COALESCE(q.percentile,0.5) AS quality,COALESCE(q.reply_rate,0.75) AS reply_rate,` + idle + ` AS idle_days,
 jsonb_build_object('gender',jsonb_build_array(p.gender_id),'religion',jsonb_build_array(p.religion_id),'university',jsonb_build_array(p.university_id),'personality',jsonb_build_array(p.personality_type_id),'hobby',COALESCE((SELECT jsonb_agg(hobby_id) FROM profile_hobbies WHERE user_id=p.user_id),'[]'::jsonb),'looking_for',COALESCE((SELECT jsonb_agg(looking_for_id) FROM profile_looking_for WHERE user_id=p.user_id),'[]'::jsonb)) AS catalog,
 CASE WHEN ` + and(exact) + ` THEN 0 ELSE 1 END AS tier,
 ` + fmt.Sprint(DescribeRelevanceWeight) + `*(` + relevance + `)+` + fmt.Sprint(DescribeQualityWeight) + `*(` + quality + `)+` + fmt.Sprint(DescribeDistanceWeight) + `*GREATEST(0,1-` + fmt.Sprint(DescribeDistanceFalloff) + `*public.ST_Distance(l.location,vl.location)/1000/GREATEST($2,0.001)) AS score` + from + ` AND ` + and(close) + ` AND NOT(COALESCE(q.completed_matches,0)>=10 AND COALESCE(q.reply_rate,0.75)<0.2)), ranked AS (SELECT *,row_number() OVER(PARTITION BY tier ORDER BY score DESC,distance,user_id) AS position FROM eligible) SELECT snapshot,user_id,gender_id,age,distance,active,height_cm,bio,ambition,quality,reply_rate,idle_days,catalog FROM ranked WHERE position<=10 ORDER BY tier,score DESC,distance,user_id LIMIT 10`
	tx, err := q.DB.BeginTx(ctx, &sql.TxOptions{ReadOnly: true, Isolation: sql.LevelRepeatableRead})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	if err = check(ctx, tx, viewer); err != nil {
		return nil, err
	}
	rows, err := tx.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	out := []FilteredCandidate{}
	for rows.Next() {
		var c FilteredCandidate
		var raw []byte
		if err = rows.Scan(&c.Snapshot, &c.ID, &c.GenderID, &c.Age, &c.DistanceKM, &c.LastActiveAt, &c.HeightCM, &c.Bio, &c.Ambition, &c.Quality, &c.ReplyRate, &c.IdleDays, &raw); err != nil {
			rows.Close()
			return nil, err
		}
		// Nullable option IDs remain absent evidence rather than a satisfied preference.
		var catalog map[string][]*string
		if err = json.Unmarshal(raw, &catalog); err != nil {
			rows.Close()
			return nil, err
		}
		c.Catalog = map[string][]string{}
		for field, values := range catalog {
			for _, value := range values {
				if value != nil {
					c.Catalog[field] = append(c.Catalog[field], *value)
				}
			}
		}
		out = append(out, c)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return out, nil
}
func clauseSQL(c CandidateClause, bind func(any) string, relax bool) (string, string, error) {
	fail := func() (string, string, error) { return "", "", fmt.Errorf("invalid candidate clause") }
	numeric := map[string]string{"age": "date_part('year',age(p.birthdate))", "height_cm": "p.height_cm", "distance_km": "public.ST_Distance(l.location,vl.location)/1000"}
	if expression, ok := numeric[c.Field]; ok {
		if c.Number == nil || math.IsNaN(*c.Number) || math.IsInf(*c.Number, 0) || c.Text != "" || c.CatalogID != "" {
			return fail()
		}
		n := *c.Number
		min, max := 0.0, math.MaxFloat64
		tolerance := DescribeNumericTolerance(c.Field, n)
		if c.Field == "age" {
			min, max = 18, 150
		} else if c.Field == "height_cm" {
			min, max = 100, 250
		}
		if n < min || n > max || (c.Field != "distance_km" && n != math.Trunc(n)) {
			return fail()
		}
		v := bind(n)
		if !relax {
			op := map[string]string{"gte": ">=", "lte": "<=", "eq": "="}[c.Operator]
			if op == "" {
				return fail()
			}
			return expression + op + v, expression + op + v, nil
		}
		switch c.Operator {
		case "gte":
			if c.Field == "distance_km" {
				tolerance = 0
			}
			return expression + ">=" + v, expression + ">=" + bind(math.Max(min, n-tolerance)), nil
		case "lte":
			return expression + "<=" + v, expression + "<=" + bind(n+tolerance), nil
		case "eq":
			lower := math.Max(min, n-tolerance)
			if c.Field == "distance_km" {
				lower = n
			}
			return expression + "=" + v, expression + " BETWEEN " + bind(lower) + " AND " + bind(n+tolerance), nil
		}
		return fail()
	}
	if c.Number != nil {
		return fail()
	}
	var predicate string
	if c.Field == "bio" || c.Field == "ambition" {
		if c.Operator != "contains" || strings.TrimSpace(c.Text) == "" || c.CatalogID != "" {
			return fail()
		}
		predicate = "strpos(lower(COALESCE(p." + c.Field + ",'')),lower(" + bind(c.Text) + "))>0"
	} else {
		if c.CatalogID == "" || c.Text != "" {
			return fail()
		}
		switch c.Field {
		case "gender", "religion", "university", "personality":
			if c.Operator != "eq" {
				return fail()
			}
			column := map[string]string{"gender": "gender_id", "religion": "religion_id", "university": "university_id", "personality": "personality_type_id"}[c.Field]
			predicate = "p." + column + "::text=" + bind(c.CatalogID)
		case "hobby", "looking_for":
			if c.Operator != "contains" {
				return fail()
			}
			table, column := "profile_hobbies", "hobby_id"
			if c.Field == "looking_for" {
				table, column = "profile_looking_for", "looking_for_id"
			}
			predicate = "EXISTS(SELECT 1 FROM " + table + " f WHERE f.user_id=p.user_id AND f." + column + "::text=" + bind(c.CatalogID) + ")"
		default:
			return fail()
		}
	}
	return predicate, predicate, nil
}
