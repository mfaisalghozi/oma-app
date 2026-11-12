-- Local development consent documents. NOT approved legal copy.
--
-- The legal document registry is deliberately empty in migrations: an operator
-- inserts approved agreements before onboarding is enabled, and an empty
-- registry fails closed. See "Legal document registry" in ../README.md.
--
-- This file exists so a disposable or local database can complete onboarding
-- during development and regression. The URLs are placeholders that match
-- `webBaseUrl` in the mobile config. Do not apply this file to a shared,
-- staging or production database.
--
-- Apply it after migrations:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f catalogs/dev-consent-documents.sql
--
-- The insert is idempotent, so a repeated run does nothing.

BEGIN;

INSERT INTO consent_documents(consent_type, document_version, title, document_url, required, active) VALUES
 ('terms',          '1.0', 'Terms of Service',      'https://oma.app/terms',          true, true),
 ('privacy',        '1.0', 'Privacy Policy',        'https://oma.app/privacy',        true, true),
 ('sensitive_data', '1.0', 'Sensitive Data Notice', 'https://oma.app/sensitive-data', true, true)
ON CONFLICT(consent_type, document_version) DO NOTHING;

COMMIT;
