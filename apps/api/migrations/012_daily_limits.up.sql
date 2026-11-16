CREATE TABLE daily_limit_operations (
 owner_id UUID NOT NULL REFERENCES accounts(user_id),
 meter TEXT NOT NULL CHECK (meter IN ('likes','searches')),
 operation_id UUID NOT NULL,
 bucket DATE NOT NULL,
 units INTEGER NOT NULL CHECK (units > 0),
 payload_hash TEXT NOT NULL CHECK (length(payload_hash) BETWEEN 1 AND 256),
 state TEXT NOT NULL CHECK (state IN ('reserved','settled','released')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY (owner_id,meter,operation_id)
);
CREATE INDEX daily_limit_operations_usage ON daily_limit_operations(owner_id,bucket,meter) WHERE state <> 'released';
ALTER TABLE daily_limit_operations ENABLE ROW LEVEL SECURITY;
