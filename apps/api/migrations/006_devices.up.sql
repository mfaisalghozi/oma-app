CREATE TABLE device_tokens (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id UUID NOT NULL REFERENCES accounts(user_id),
 token TEXT NOT NULL UNIQUE CHECK(char_length(token)>0 AND octet_length(token)<=8192),
 platform TEXT NOT NULL CHECK(platform IN ('ios','android')),
 provider TEXT NOT NULL CHECK(provider IN ('fcm','apns')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX device_owner ON device_tokens(user_id);
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
