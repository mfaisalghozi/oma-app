ALTER TABLE profiles ADD COLUMN revision BIGINT NOT NULL DEFAULT 1, ADD COLUMN preference_revision BIGINT NOT NULL DEFAULT 1, ADD COLUMN random_key DOUBLE PRECISION NOT NULL DEFAULT random();
CREATE INDEX idx_profiles_random_key ON profiles(random_key,user_id);
ALTER TABLE user_locations ADD COLUMN location_version BIGINT NOT NULL DEFAULT 1;
CREATE FUNCTION discovery_profile_revision() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 NEW.revision=OLD.revision+1;
 IF ROW(NEW.birthdate,NEW.gender_id,NEW.show_me_option_id,NEW.min_age,NEW.max_age,NEW.radius_km) IS DISTINCT FROM ROW(OLD.birthdate,OLD.gender_id,OLD.show_me_option_id,OLD.min_age,OLD.max_age,OLD.radius_km) THEN NEW.preference_revision=OLD.preference_revision+1; END IF;
 RETURN NEW; END $$;
CREATE TRIGGER discovery_profile_revision BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION discovery_profile_revision();
-- A location write invalidates the cache; movement threshold is evaluated in the cache fingerprint.
CREATE FUNCTION discovery_location_revision() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.location_version=OLD.location_version+1;RETURN NEW;END $$;
CREATE TRIGGER discovery_location_revision BEFORE UPDATE OF location ON user_locations FOR EACH ROW EXECUTE FUNCTION discovery_location_revision();
CREATE TABLE deck_cache (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),viewer_id UUID NOT NULL REFERENCES accounts(user_id),generation BIGINT NOT NULL,
 exposure_bucket_date DATE NOT NULL,preference_revision BIGINT NOT NULL,location_version BIGINT NOT NULL,location public.GEOGRAPHY(POINT,4326) NOT NULL,
 policy_version TEXT NOT NULL,ranking_version TEXT NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),expires_at TIMESTAMPTZ NOT NULL,status TEXT NOT NULL DEFAULT 'active' CHECK(status IN('active','expired')),
 UNIQUE(viewer_id,generation)
);
CREATE UNIQUE INDEX deck_cache_one_active ON deck_cache(viewer_id) WHERE status='active';
CREATE TABLE deck_cache_cards (
 batch_id UUID NOT NULL REFERENCES deck_cache(id),candidate_id UUID NOT NULL REFERENCES accounts(user_id),position INT NOT NULL CHECK(position BETWEEN 1 AND 20),selection_bucket TEXT NOT NULL,bypass_reason TEXT,action_id UUID,delivered_at TIMESTAMPTZ,
 PRIMARY KEY(batch_id,candidate_id),UNIQUE(batch_id,position)
);
CREATE TABLE deck_cursors(id UUID PRIMARY KEY DEFAULT gen_random_uuid(),batch_id UUID NOT NULL REFERENCES deck_cache(id),position INT NOT NULL CHECK(position BETWEEN 0 AND 20),UNIQUE(batch_id,position));
CREATE TABLE discovery_exposures(viewer_id UUID NOT NULL REFERENCES accounts(user_id),candidate_id UUID NOT NULL REFERENCES accounts(user_id),bucket_date DATE NOT NULL,delivered_at TIMESTAMPTZ NOT NULL,PRIMARY KEY(viewer_id,candidate_id,bucket_date));
CREATE TABLE candidate_daily_exposures(candidate_id UUID NOT NULL REFERENCES accounts(user_id),bucket_date DATE NOT NULL,shown_today INT NOT NULL DEFAULT 0 CHECK(shown_today>=0),PRIMARY KEY(candidate_id,bucket_date));
CREATE VIEW discovery_quality AS SELECT NULL::uuid AS candidate_id,NULL::text AS segment_key,0::double precision AS likes_w,0::double precision AS passes_w,0.5::double precision AS percentile,0.75::double precision AS reply_rate,NULL::double precision AS prior_mean,0::bigint AS completed_matches WHERE false;
CREATE VIEW discovery_incoming_priority AS SELECT NULL::uuid AS viewer_id,NULL::uuid AS candidate_id,NULL::timestamptz AS created_at WHERE false;
ALTER TABLE deck_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE deck_cache_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE deck_cursors ENABLE ROW LEVEL SECURITY;
ALTER TABLE discovery_exposures ENABLE ROW LEVEL SECURITY;
ALTER TABLE candidate_daily_exposures ENABLE ROW LEVEL SECURITY;
