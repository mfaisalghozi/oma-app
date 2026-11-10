CREATE TABLE photos (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id UUID NOT NULL REFERENCES accounts(user_id),
 storage_path TEXT NOT NULL UNIQUE,
 content_type TEXT NOT NULL CHECK(content_type IN ('image/jpeg','image/png','image/webp')),
 file_size BIGINT NOT NULL CHECK(file_size BETWEEN 1 AND 10485760),
 position SMALLINT CHECK(position BETWEEN 1 AND 6),
 is_primary BOOLEAN NOT NULL DEFAULT false,
 status TEXT NOT NULL DEFAULT 'pending_upload' CHECK(status IN ('pending_upload','active','deleted')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CONSTRAINT unique_photo_position UNIQUE(user_id,position) DEFERRABLE INITIALLY DEFERRED,
 CHECK((status='active' AND position IS NOT NULL) OR (status<>'active' AND position IS NULL AND NOT is_primary))
);
CREATE UNIQUE INDEX one_primary_photo ON photos(user_id) WHERE is_primary AND status='active';
CREATE INDEX photos_owner ON photos(user_id,status);
ALTER TABLE photos ENABLE ROW LEVEL SECURITY;
