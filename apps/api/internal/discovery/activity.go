package discovery

import (
	"context"
	"database/sql"
)

func RecordActivity(ctx context.Context, db *sql.DB, viewer string) error {
	_, err := db.ExecContext(ctx, `INSERT INTO discovery_activity(user_id,last_active_at) VALUES($1,clock_timestamp()) ON CONFLICT(user_id) DO UPDATE SET last_active_at=EXCLUDED.last_active_at WHERE discovery_activity.last_active_at<clock_timestamp()-interval '1 minute'`, viewer)
	return err
}
