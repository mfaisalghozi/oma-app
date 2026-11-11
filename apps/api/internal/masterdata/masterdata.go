package masterdata

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"oma/apps/api/internal/platform/httpapi"
	"strconv"
	"unicode/utf8"
)

type Handler struct{ DB *sql.DB }

// Every supported type maps to a full literal query; user input never becomes a SQL identifier.
var queries = map[string]string{
	"gender":         `WITH filtered AS (SELECT id, code, label FROM gender_options WHERE is_active AND strpos(lower(label),lower($1))>0 AND $2::text='') SELECT COALESCE((SELECT jsonb_agg(to_jsonb(page)) FROM (SELECT * FROM filtered ORDER BY id LIMIT $3 OFFSET $4) page),'[]'::jsonb),(SELECT count(*) FROM filtered)`,
	"pronoun":        `WITH filtered AS (SELECT id, code, label FROM pronoun_options WHERE is_active AND strpos(lower(label),lower($1))>0 AND $2::text='') SELECT COALESCE((SELECT jsonb_agg(to_jsonb(page)) FROM (SELECT * FROM filtered ORDER BY id LIMIT $3 OFFSET $4) page),'[]'::jsonb),(SELECT count(*) FROM filtered)`,
	"show_me":        `WITH filtered AS (SELECT id, code, label FROM show_me_options WHERE is_active AND strpos(lower(label),lower($1))>0 AND $2::text='') SELECT COALESCE((SELECT jsonb_agg(to_jsonb(page)) FROM (SELECT * FROM filtered ORDER BY id LIMIT $3 OFFSET $4) page),'[]'::jsonb),(SELECT count(*) FROM filtered)`,
	"looking_for":    `WITH filtered AS (SELECT id, code, label FROM looking_for_options WHERE is_active AND strpos(lower(label),lower($1))>0 AND $2::text='') SELECT COALESCE((SELECT jsonb_agg(to_jsonb(page)) FROM (SELECT * FROM filtered ORDER BY id LIMIT $3 OFFSET $4) page),'[]'::jsonb),(SELECT count(*) FROM filtered)`,
	"religion":       `WITH filtered AS (SELECT id, code, label FROM religions WHERE is_active AND strpos(lower(label),lower($1))>0 AND $2::text='') SELECT COALESCE((SELECT jsonb_agg(to_jsonb(page)) FROM (SELECT * FROM filtered ORDER BY id LIMIT $3 OFFSET $4) page),'[]'::jsonb),(SELECT count(*) FROM filtered)`,
	"personality":    `WITH filtered AS (SELECT id, code, label FROM personality_types WHERE is_active AND strpos(lower(label),lower($1))>0 AND $2::text='') SELECT COALESCE((SELECT jsonb_agg(to_jsonb(page)) FROM (SELECT * FROM filtered ORDER BY id LIMIT $3 OFFSET $4) page),'[]'::jsonb),(SELECT count(*) FROM filtered)`,
	"hobby_category": `WITH filtered AS (SELECT id, code, label FROM hobby_categories WHERE is_active AND strpos(lower(label),lower($1))>0 AND $2::text='') SELECT COALESCE((SELECT jsonb_agg(to_jsonb(page)) FROM (SELECT * FROM filtered ORDER BY id LIMIT $3 OFFSET $4) page),'[]'::jsonb),(SELECT count(*) FROM filtered)`,
	"university":     `WITH filtered AS (SELECT id,name,country_code FROM universities WHERE is_active AND strpos(lower(name),lower($1))>0 AND $2::text='') SELECT COALESCE((SELECT jsonb_agg(to_jsonb(page)) FROM (SELECT * FROM filtered ORDER BY id LIMIT $3 OFFSET $4) page),'[]'::jsonb),(SELECT count(*) FROM filtered)`,
	"hobby":          `WITH filtered AS (SELECT h.id,h.category_id,h.code,h.label FROM hobbies h JOIN hobby_categories c ON c.id=h.category_id WHERE h.is_active AND c.is_active AND strpos(lower(h.label),lower($1))>0 AND ($2::text='' OR h.category_id=NULLIF($2,'')::uuid)) SELECT COALESCE((SELECT jsonb_agg(to_jsonb(page)) FROM (SELECT * FROM filtered ORDER BY id LIMIT $3 OFFSET $4) page),'[]'::jsonb),(SELECT count(*) FROM filtered)`,
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	kind := q.Get("type")
	query, ok := queries[kind]
	if !ok {
		httpapi.Fail(w, 400, "INVALID_MASTER_DATA_TYPE")
		return
	}
	category := q.Get("category_id")
	if category != "" && (kind != "hobby" || !httpapi.ValidID(category)) {
		httpapi.Fail(w, 400, "INVALID_QUERY_PARAMETERS")
		return
	}
	parse := func(name string, def, max int) (int, bool) {
		s := q.Get(name)
		if s == "" {
			return def, true
		}
		n, e := strconv.Atoi(s)
		return n, e == nil && n > 0 && n <= max
	}
	page, okPage := parse("page", 1, 1000000)
	limit, okLimit := parse("limit", 20, 100)
	if !okPage || !okLimit || utf8.RuneCountInString(q.Get("q")) > 100 {
		httpapi.Fail(w, 400, "INVALID_QUERY_PARAMETERS")
		return
	}
	var items json.RawMessage
	var total int
	err := h.DB.QueryRowContext(r.Context(), query, q.Get("q"), category, limit, (page-1)*limit).Scan(&items, &total)
	if err != nil {
		httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
		return
	}
	httpapi.Data(w, 200, map[string]any{"type": kind, "items": items, "pagination": map[string]int{"page": page, "limit": limit, "total": total, "total_pages": (total + limit - 1) / limit}})
}
