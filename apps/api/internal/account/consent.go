package account

import (
	"context"
	"database/sql"
	"oma/apps/api/internal/platform/httpapi"
)

type ConsentQuery interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

// RequiredConsentsComplete evaluates the shared SQL policy, including latest revocations.
func RequiredConsentsComplete(ctx context.Context, q ConsentQuery, id string) (bool, error) {
	var ok bool
	err := q.QueryRowContext(ctx, `SELECT required_consents_completed($1)`, id).Scan(&ok)
	return ok, err
}
func RequireConsents(ctx context.Context, q ConsentQuery, id string) error {
	ok, err := RequiredConsentsComplete(ctx, q, id)
	if err != nil {
		return err
	}
	if !ok {
		return &httpapi.Error{Status: 403, Code: "CONSENT_REQUIRED"}
	}
	return nil
}
