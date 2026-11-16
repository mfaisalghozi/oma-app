package describe

import (
	"errors"
	"fmt"
	"math"
	"oma/apps/api/internal/discovery"
	"strings"
)

var ErrNoSearchableCriteria = errors.New("add a supported age, height, distance, profile option or authored text criterion")

type Evidence struct {
	ID                  string
	Age, HeightCM       int
	DistanceKM, Quality float64
	Bio, Ambition       string
	Catalog             map[string][]string
}
type Violation struct {
	Criterion Criterion `json:"criterion"`
	Deviation float64   `json:"deviation"`
}
type Evaluation struct {
	Tier       string      `json:"tier"`
	Matched    int         `json:"matched"`
	Total      int         `json:"total"`
	Reason     string      `json:"reason"`
	Violations []Violation `json:"violated_criteria"`
	Score      float64     `json:"-"`
}

func Evaluate(c Criteria, e Evidence, maxDistanceKM float64) (Evaluation, error) {
	out := Evaluation{Tier: "exact", Total: len(c.Must) + len(c.Nice), Violations: []Violation{}}
	if len(c.Must)+len(c.Nice) == 0 {
		return out, ErrNoSearchableCriteria
	}
	if maxDistanceKM < 0 || math.IsNaN(maxDistanceKM) || math.IsInf(maxDistanceKM, 0) || e.Age < 0 || e.DistanceKM < 0 || math.IsNaN(e.DistanceKM) || math.IsInf(e.DistanceKM, 0) || e.Quality < 0 || e.Quality > 1 || math.IsNaN(e.Quality) {
		return out, ErrInvalidCriteria
	}
	if e.DistanceKM > maxDistanceKM || (e.Age > 0 && e.Age < 18) {
		out.Tier = "excluded"
	}
	reasons := []string{}
	niceMatched := 0
	for group, list := range [][]Criterion{c.Must, c.Nice} {
		for _, criterion := range list {
			if criterion.Number != nil && (math.IsNaN(*criterion.Number) || math.IsInf(*criterion.Number, 0)) {
				return Evaluation{}, ErrInvalidCriteria
			}
			matched, deviation, tolerance := match(criterion, e)
			if matched {
				out.Matched++
				if group == 1 {
					niceMatched++
				}
				label := map[string]string{"height_cm": "height", "age": "age", "distance_km": "distance", "bio": "bio", "ambition": "ambition", "gender": "gender", "religion": "religion", "university": "university", "personality": "personality", "hobby": "hobby", "looking_for": "relationship preference"}[criterion.Field]
				reasons = append(reasons, label)
				continue
			}
			if group == 0 {
				if tolerance == 0 || deviation > tolerance || e.DistanceKM > maxDistanceKM || (criterion.Field == "age" && e.Age < 18) {
					out.Tier = "excluded"
				} else if out.Tier != "excluded" {
					out.Tier = "close"
				}
				out.Violations = append(out.Violations, Violation{Criterion: criterion, Deviation: deviation})
			}
		}
	}
	relevance := 1.0
	if len(c.Nice) > 0 {
		relevance = float64(niceMatched) / float64(len(c.Nice))
	}
	out.Score = discovery.DescribeRelevanceWeight*relevance + discovery.DescribeQualityWeight*e.Quality + discovery.DescribeDistanceWeight*math.Max(0, 1-e.DistanceKM/math.Max(maxDistanceKM, 0.001))
	out.Reason = fmt.Sprintf("Matched %d of %d criteria", out.Matched, out.Total)
	if len(reasons) > 0 {
		out.Reason += ": " + strings.Join(reasons, ", ")
	}
	return out, nil
}
func match(c Criterion, e Evidence) (bool, float64, float64) {
	if c.Number != nil {
		var value, tolerance float64
		switch c.Field {
		case "age":
			value = float64(e.Age)
			tolerance = discovery.DescribeNumericTolerance(c.Field, *c.Number)
		case "height_cm":
			value = float64(e.HeightCM)
			tolerance = discovery.DescribeNumericTolerance(c.Field, *c.Number)
		case "distance_km":
			value = e.DistanceKM
			tolerance = discovery.DescribeNumericTolerance(c.Field, *c.Number)
		default:
			return false, 0, 0
		}
		deviation := math.Abs(value - *c.Number)
		switch c.Operator {
		case "gte":
			if c.Field == "distance_km" {
				tolerance = 0
			}
			deviation = math.Max(0, *c.Number-value)
		case "lte":
			deviation = math.Max(0, value-*c.Number)
		case "eq":
			if c.Field == "distance_km" && value < *c.Number {
				tolerance = 0
			}
		default:
			return false, 0, 0
		}
		return deviation == 0, deviation, tolerance
	}
	if c.Field == "bio" || c.Field == "ambition" {
		value := e.Bio
		if c.Field == "ambition" {
			value = e.Ambition
		}
		return c.Text != "" && strings.Contains(strings.ToLower(value), strings.ToLower(c.Text)), 0, 0
	}
	for _, v := range e.Catalog[c.Field] {
		if c.CatalogID != "" && v == c.CatalogID {
			return true, 0, 0
		}
	}
	return false, 0, 0
}
