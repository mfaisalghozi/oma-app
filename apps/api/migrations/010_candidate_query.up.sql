ALTER TABLE profiles
 ADD COLUMN min_age SMALLINT CHECK(min_age>=18),
 ADD COLUMN max_age SMALLINT CHECK(max_age>=18),
 ADD COLUMN radius_km DOUBLE PRECISION CHECK(radius_km>0 AND radius_km<'Infinity'::double precision),
 ADD CONSTRAINT profiles_age_preference_order CHECK(min_age IS NULL OR max_age IS NULL OR min_age<=max_age);
CREATE TABLE user_blocks (
 blocker_id UUID NOT NULL REFERENCES accounts(user_id),
 blocked_id UUID NOT NULL REFERENCES accounts(user_id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(blocker_id,blocked_id),
 CHECK(blocker_id<>blocked_id)
);
CREATE INDEX user_blocks_reverse ON user_blocks(blocked_id,blocker_id);
ALTER TABLE user_blocks ENABLE ROW LEVEL SECURITY;
CREATE TABLE discovery_activity (
 user_id UUID PRIMARY KEY REFERENCES accounts(user_id),
 last_active_at TIMESTAMPTZ NOT NULL
);
ALTER TABLE discovery_activity ENABLE ROW LEVEL SECURITY;
-- DSC-BE-03 replaces this read contract with directed decisions and canonical matches.
-- There are no persisted actions or matches before that ticket is installed.
CREATE VIEW discovery_pair_exclusions AS
 SELECT NULL::uuid AS viewer_id,NULL::uuid AS candidate_id WHERE false;
