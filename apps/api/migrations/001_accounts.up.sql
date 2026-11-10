CREATE TABLE accounts (
 user_id UUID PRIMARY KEY,
 status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','frozen','suspended')),
 onboarding_completed_at TIMESTAMPTZ,
 suspended_until TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
