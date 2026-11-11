package database

import (
	"context"
	"database/sql"
	"errors"
	_ "github.com/jackc/pgx/v5/stdlib"
	"time"
)

func Open(ctx context.Context, url string) (*sql.DB, error) {
	if url == "" {
		return nil, errors.New("DATABASE_URL is required")
	}
	db, err := sql.Open("pgx", url)
	if err != nil {
		return nil, errors.New("invalid database configuration")
	}
	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(30 * time.Minute)
	if err = db.PingContext(ctx); err != nil {
		db.Close()
		return nil, errors.New("database unavailable")
	}
	return db, nil
}
