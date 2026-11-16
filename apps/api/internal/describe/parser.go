package describe

import (
	"context"
	"encoding/json"
	"errors"
	"time"
)

var ErrProvider = errors.New("describe provider unavailable")

type JSONProvider interface {
	Generate(context.Context, string) ([]byte, error)
}
type Parser struct {
	Provider JSONProvider
	Catalog  []CatalogEntry
	Limits   Limits
}

func (p Parser) Parse(ctx context.Context, query string) (Criteria, error) {
	if !validText(query, 500) || !p.Limits.valid() {
		return Criteria{}, ErrInvalidCriteria
	}
	if p.Provider == nil {
		return Criteria{}, ErrProvider
	}
	prompt, err := json.Marshal(struct {
		Query         string         `json:"query"`
		Catalog       []CatalogEntry `json:"catalog"`
		MaxAge        int            `json:"max_age"`
		MaxDistanceKM float64        `json:"max_distance_km"`
	}{query, p.Catalog, p.Limits.MaxAge, p.Limits.MaxDistanceKM})
	if err != nil {
		return Criteria{}, ErrInvalidCriteria
	}
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	raw, err := p.Provider.Generate(ctx, string(prompt))
	if err != nil {
		return Criteria{}, ErrProvider
	}
	return Decode(query, raw, p.Catalog, p.Limits)
}
