CREATE TABLE describe_searches (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 owner_id UUID NOT NULL REFERENCES accounts(user_id),
 request_id UUID NOT NULL,
 query TEXT NOT NULL CHECK(length(query) BETWEEN 1 AND 500),
 payload_hash TEXT NOT NULL,
 retry_of UUID REFERENCES describe_searches(id),
 phase TEXT NOT NULL DEFAULT 'queued' CHECK(phase IN ('queued','parsing','retrieving','ranking')),
 parser_version TEXT NOT NULL,
 ranking_policy_version TEXT NOT NULL,
 policy_version TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','running','succeeded','failed')),
 criteria JSONB,
 requested_radius_km DOUBLE PRECISION,
 effective_radius_km DOUBLE PRECISION,
 error_code TEXT,
 lease_token UUID,
 lease_until TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 completed_at TIMESTAMPTZ,
 UNIQUE(owner_id,request_id),
 CHECK((state='running')=(lease_token IS NOT NULL AND lease_until IS NOT NULL)),
 CHECK(state<>'succeeded' OR (criteria IS NOT NULL AND effective_radius_km>=0))
);
CREATE UNIQUE INDEX describe_one_inflight ON describe_searches(owner_id) WHERE state IN ('pending','running');
CREATE INDEX describe_pending ON describe_searches(state,created_at);
CREATE TABLE describe_search_request_keys (
 owner_id UUID NOT NULL REFERENCES accounts(user_id),
 key_hash TEXT NOT NULL,
 search_id UUID NOT NULL REFERENCES describe_searches(id),
 expires_at TIMESTAMPTZ NOT NULL,
 PRIMARY KEY(owner_id,key_hash)
);
CREATE INDEX describe_request_expiry ON describe_search_request_keys(expires_at);
ALTER TABLE describe_search_request_keys ENABLE ROW LEVEL SECURITY;
CREATE TABLE describe_search_results (
 search_id UUID NOT NULL REFERENCES describe_searches(id) ON DELETE CASCADE,
 candidate_id UUID NOT NULL REFERENCES accounts(user_id),
 position INTEGER NOT NULL CHECK(position BETWEEN 1 AND 10),
 profile_revision BIGINT NOT NULL,
 evidence_snapshot TEXT NOT NULL,
 evaluation JSONB NOT NULL,
 delivered_at TIMESTAMPTZ,
 PRIMARY KEY(search_id,candidate_id), UNIQUE(search_id,position)
);
ALTER TABLE describe_searches ENABLE ROW LEVEL SECURITY;
ALTER TABLE describe_search_results ENABLE ROW LEVEL SECURITY;
