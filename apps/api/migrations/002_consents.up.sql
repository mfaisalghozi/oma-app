CREATE TABLE consent_documents (
 consent_type TEXT NOT NULL CHECK (consent_type IN ('terms','privacy','sensitive_data')),
 document_version TEXT NOT NULL,
 title TEXT NOT NULL,
 document_url TEXT NOT NULL,
 required BOOLEAN NOT NULL DEFAULT true,
 active BOOLEAN NOT NULL DEFAULT false,
 PRIMARY KEY(consent_type,document_version)
);
CREATE UNIQUE INDEX one_active_consent_document ON consent_documents(consent_type) WHERE active;
CREATE TABLE user_consents (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 sequence BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE,
 user_id UUID NOT NULL REFERENCES accounts(user_id),
 consent_type TEXT NOT NULL,
 document_version TEXT NOT NULL,
 decision TEXT NOT NULL CHECK(decision IN ('accepted','rejected','revoked')),
 recorded_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(consent_type,document_version) REFERENCES consent_documents(consent_type,document_version)
);
CREATE INDEX consent_latest ON user_consents(user_id,consent_type,sequence DESC);
CREATE FUNCTION preserve_consent_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'consent history is append only'; END;
$$;
CREATE TRIGGER consent_history_immutable BEFORE UPDATE OR DELETE ON user_consents
FOR EACH ROW EXECUTE FUNCTION preserve_consent_history();
ALTER TABLE consent_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_consents ENABLE ROW LEVEL SECURITY;
