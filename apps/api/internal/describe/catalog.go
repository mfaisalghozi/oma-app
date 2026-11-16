package describe

import (
	"context"
	"database/sql"
)

func LoadCatalog(ctx context.Context, db *sql.DB) ([]CatalogEntry, error) {
	rows, err := db.QueryContext(ctx, `SELECT 'gender',id::text,label,code FROM gender_options WHERE is_active
 UNION ALL SELECT 'religion',id::text,label,code FROM religions WHERE is_active
 UNION ALL SELECT 'personality',id::text,label,code FROM personality_types WHERE is_active
 UNION ALL SELECT 'university',id::text,name,name FROM universities WHERE is_active
 UNION ALL SELECT 'hobby',id::text,label,code FROM hobbies WHERE is_active
 UNION ALL SELECT 'looking_for',id::text,label,code FROM looking_for_options WHERE is_active`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []CatalogEntry{}
	for rows.Next() {
		var c CatalogEntry
		var alias string
		if err = rows.Scan(&c.Field, &c.ID, &c.Label, &alias); err != nil {
			return nil, err
		}
		c.Aliases = []string{alias}
		out = append(out, c)
	}
	return out, rows.Err()
}
