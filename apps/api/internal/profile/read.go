package profile

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"oma/apps/api/internal/media"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
)

func (h *Handler) Read(w http.ResponseWriter, r *http.Request) {
	var raw []byte
	err := h.DB.QueryRowContext(r.Context(), `SELECT jsonb_build_object(
 'user_id',p.user_id,'full_name',p.full_name,'birthdate',p.birthdate,
 'gender',jsonb_build_object('id',g.id,'code',g.code,'label',g.label),
 'pronoun',CASE WHEN pn.id IS NULL THEN NULL ELSE jsonb_build_object('id',pn.id,'code',pn.code,'label',pn.label) END,
 'show_me',jsonb_build_object('id',sm.id,'code',sm.code,'label',sm.label),
 'bio',p.bio,'height_cm',p.height_cm,'weight_kg',p.weight_kg,
 'university',CASE WHEN u.id IS NULL THEN NULL ELSE jsonb_build_object('id',u.id,'name',u.name,'country_code',u.country_code) END,
 'ambition',p.ambition,
 'religion',CASE WHEN rel.id IS NULL THEN NULL ELSE jsonb_build_object('id',rel.id,'code',rel.code,'label',rel.label) END,
 'personality',CASE WHEN mb.id IS NULL THEN NULL ELSE jsonb_build_object('id',mb.id,'code',mb.code,'label',mb.label) END,
 'looking_for',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',lf.id,'code',lf.code,'label',lf.label) ORDER BY lf.code) FROM profile_looking_for pl JOIN looking_for_options lf ON lf.id=pl.looking_for_id WHERE pl.user_id=p.user_id),'[]'::jsonb),
 'hobbies',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',ho.id,'category_id',ho.category_id,'code',ho.code,'label',ho.label) ORDER BY ho.code) FROM profile_hobbies ph JOIN hobbies ho ON ho.id=ph.hobby_id WHERE ph.user_id=p.user_id),'[]'::jsonb),
 'created_at',p.created_at,'updated_at',p.updated_at)
 FROM profiles p
 JOIN gender_options g ON g.id=p.gender_id
 JOIN show_me_options sm ON sm.id=p.show_me_option_id
 LEFT JOIN pronoun_options pn ON pn.id=p.pronoun_id
 LEFT JOIN universities u ON u.id=p.university_id
 LEFT JOIN religions rel ON rel.id=p.religion_id
 LEFT JOIN personality_types mb ON mb.id=p.personality_type_id
 WHERE p.user_id=$1`, auth.UserID(r.Context())).Scan(&raw)
	if err == sql.ErrNoRows {
		httpapi.Fail(w, 404, "PROFILE_NOT_FOUND")
		return
	}
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	var out map[string]any
	if err = json.Unmarshal(raw, &out); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	photos, err := media.List(r.Context(), h.DB, h.Store, auth.UserID(r.Context()))
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	active := []media.Photo{}
	for _, p := range photos {
		if p.Status == "active" {
			active = append(active, p)
		}
	}
	out["photos"] = active
	httpapi.Data(w, 200, out)
}
