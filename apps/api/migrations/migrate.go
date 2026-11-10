package migrations

import (
	"context"
	"database/sql"
	"embed"
	"fmt"
	"io/fs"
	"sort"
	"strings"
)

//go:embed *.sql
var scripts embed.FS

func Up(ctx context.Context, db *sql.DB) error {
	names, err := fs.Glob(scripts, "*.up.sql")
	if err != nil {
		return err
	}
	sort.Strings(names)
	for _, name := range names {
		if err = apply(ctx, db, name, false); err != nil {
			return err
		}
	}
	return nil
}

// Down reverts only the most recent applied migration.
func Down(ctx context.Context, db *sql.DB) error { return apply(ctx, db, "", true) }
func apply(ctx context.Context, db *sql.DB, name string, down bool) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(74761239)`); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`); err != nil {
		return err
	}
	version := strings.TrimSuffix(name, ".up.sql")
	if down {
		err = tx.QueryRowContext(ctx, `SELECT name FROM schema_migrations ORDER BY name DESC LIMIT 1`).Scan(&version)
		if err == sql.ErrNoRows {
			return tx.Commit()
		}
		if err != nil {
			return err
		}
		name = version + ".down.sql"
	} else {
		var exists bool
		if err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE name=$1)`, version).Scan(&exists); err != nil {
			return err
		}
		if exists {
			return tx.Commit()
		}
	}
	data, err := scripts.ReadFile(name)
	if err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, string(data)); err != nil {
		return fmt.Errorf("migration %s: %w", name, err)
	}
	if down {
		_, err = tx.ExecContext(ctx, `DELETE FROM schema_migrations WHERE name=$1`, version)
	} else {
		_, err = tx.ExecContext(ctx, `INSERT INTO schema_migrations(name) VALUES($1)`, version)
	}
	if err != nil {
		return err
	}
	return tx.Commit()
}
