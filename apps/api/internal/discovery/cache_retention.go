package discovery

import (
	"context"
	"database/sql"
	"time"
)

// PruneCachesTx removes at most 1000 expired caches older than seven days.
// The caller owns the transaction; exposure ledgers retain their independent history.
func PruneCachesTx(ctx context.Context, tx *sql.Tx, now time.Time) (int64, error) {
	rows, err := tx.QueryContext(ctx, `SELECT id FROM deck_cache WHERE created_at<$1 AND expires_at<=$2 ORDER BY created_at,id LIMIT 1000 FOR UPDATE SKIP LOCKED`, now.Add(-7*24*time.Hour), now)
	if err != nil {
		return 0, err
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return 0, err
		}
		ids = append(ids, id)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return 0, err
	}
	if len(ids) == 0 {
		return 0, nil
	}
	for _, query := range []string{`DELETE FROM deck_cursors WHERE batch_id=ANY($1::uuid[])`, `DELETE FROM deck_cache_cards WHERE batch_id=ANY($1::uuid[])`} {
		if _, err := tx.ExecContext(ctx, query, ids); err != nil {
			return 0, err
		}
	}
	result, err := tx.ExecContext(ctx, `DELETE FROM deck_cache WHERE id=ANY($1::uuid[])`, ids)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected()
}
