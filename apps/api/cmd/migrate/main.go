package main

import (
	"context"
	"flag"
	"log"
	"oma/apps/api/internal/platform/database"
	"oma/apps/api/migrations"
	"os"
	"time"
)

func main() {
	direction := flag.String("direction", "up", "up applies pending migrations; down reverts the latest migration")
	flag.Parse()
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	db, err := database.Open(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	switch *direction {
	case "up":
		err = migrations.Up(ctx, db)
	case "down":
		err = migrations.Down(ctx, db)
	default:
		log.Fatal("direction must be up or down")
	}
	if err != nil {
		log.Fatal("migration failed; inspect schema and migration scripts")
	}
	log.Print("migration complete")
}
