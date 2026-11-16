CREATE TABLE profile_interactions (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), actor_id UUID NOT NULL REFERENCES accounts(user_id),target_id UUID NOT NULL REFERENCES accounts(user_id),
 action TEXT NOT NULL CHECK(action IN('pass','like','super_like')),context_kind TEXT NOT NULL CHECK(context_kind IN('regular_deck','describe')),context_id UUID NOT NULL,
 created_at TIMESTAMPTZ NOT NULL, response JSONB NOT NULL DEFAULT '{}'::jsonb, UNIQUE(actor_id,target_id),CHECK(actor_id<>target_id)
);
CREATE INDEX profile_interactions_incoming ON profile_interactions(target_id,actor_id);
CREATE TABLE swipe_requests(actor_id UUID NOT NULL REFERENCES accounts(user_id),idempotency_key UUID NOT NULL,payload_hash TEXT NOT NULL,action_id UUID NOT NULL REFERENCES profile_interactions(id),PRIMARY KEY(actor_id,idempotency_key));
CREATE TABLE super_like_balances(user_id UUID PRIMARY KEY REFERENCES accounts(user_id),available INT NOT NULL DEFAULT 0 CHECK(available>=0));
CREATE TABLE matches(id UUID PRIMARY KEY DEFAULT gen_random_uuid(),user_low UUID NOT NULL REFERENCES accounts(user_id),user_high UUID NOT NULL REFERENCES accounts(user_id),created_at TIMESTAMPTZ NOT NULL,conversation_status TEXT NOT NULL DEFAULT 'pending' CHECK(conversation_status IN('pending','ready')),conversation_id UUID,UNIQUE(user_low,user_high),CHECK(user_low<user_high),CHECK((conversation_status='ready')=(conversation_id IS NOT NULL)));
CREATE TABLE swipe_events(id BIGSERIAL PRIMARY KEY,action_id UUID NOT NULL UNIQUE REFERENCES profile_interactions(id),actor_id UUID NOT NULL REFERENCES accounts(user_id),target_id UUID NOT NULL REFERENCES accounts(user_id),action TEXT NOT NULL CHECK(action IN('pass','like','super_like')),segment_key TEXT NOT NULL,occurred_at TIMESTAMPTZ NOT NULL);
CREATE FUNCTION immutable_swipe_event() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'swipe events are append-only'; END $$;
CREATE TRIGGER immutable_swipe_event BEFORE UPDATE OR DELETE ON swipe_events FOR EACH ROW EXECUTE FUNCTION immutable_swipe_event();
CREATE OR REPLACE VIEW discovery_pair_exclusions AS SELECT actor_id AS viewer_id,target_id AS candidate_id FROM profile_interactions UNION SELECT user_low,user_high FROM matches UNION SELECT user_high,user_low FROM matches;
CREATE OR REPLACE VIEW discovery_incoming_priority AS SELECT target_id AS viewer_id,actor_id AS candidate_id,created_at FROM profile_interactions WHERE action='super_like';
ALTER TABLE profile_interactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE swipe_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE super_like_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE swipe_events ENABLE ROW LEVEL SECURITY;
