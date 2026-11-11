-- Apply deliberately to the selected Supabase project before starting the API.
-- This is separate from app migrations: local integration DBs have no storage schema.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES ('profile-photos','profile-photos',false,10485760,
 ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=10485760,
 allowed_mime_types=EXCLUDED.allowed_mime_types;
-- Do not add authenticated/public INSERT or UPDATE policies for this bucket.
-- Uploads use backend-issued signed capabilities with upsert disabled.
-- Audit pre-existing storage.objects policies before staging verification.
