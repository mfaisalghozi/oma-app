package describe

import (
	"context"
	"database/sql"

	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/limits"
	"oma/apps/api/internal/platform/storage"
)

func NewService(ctx context.Context, db *sql.DB, store storage.Store, policy discovery.Policy, benefits *limits.Service, provider JSONProvider) (*Service, error) {
	s := &Service{DB: db, Limits: benefits, Parser: Parser{Provider: provider, Limits: Limits{MaxAge: policy.DefaultMaxAge, MaxDistanceKM: policy.MaxRadiusKM}}, Retriever: Retriever{Query: discovery.CandidateQuery{DB: db, Policy: discovery.CandidatePolicy{DefaultRadiusKM: policy.DefaultRadiusKM, MaxRadiusKM: policy.MaxRadiusKM, DefaultMinAge: policy.DefaultMinAge, DefaultMaxAge: policy.DefaultMaxAge, LocationFreshDays: policy.LocationFreshDays, IdleDays: 14}}, Profiles: &discovery.Handler{DB: db, Store: store, Policy: policy}}}
	var err error
	if provider != nil {
		if err = policy.Validate(); err != nil {
			return nil, err
		}
		s.Parser.Catalog, err = LoadCatalog(ctx, db)
		if err != nil {
			return nil, err
		}
	}
	s.Client, err = NewInsertClient(db)
	return s, err
}
