#!/usr/bin/env sh
# Seed a local or disposable database after migrations.
#
# Migrations deliberately do not apply either file:
#   - catalogs/initial-review.sql holds the approved catalog values.
#   - catalogs/dev-consent-documents.sql holds placeholder legal copy for local
#     work only. Never run this script against a shared, staging or production
#     database.
#
# Usage:
#   DATABASE_URL='postgresql://postgres:oma_test@127.0.0.1:55432/oma_dev' \
#     ./scripts/seed-local.sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"

if ! command -v psql >/dev/null 2>&1; then
  echo "psql not found; run this script where psql is available, or apply the two SQL files with your SQL client" >&2
  exit 1
fi

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$here/catalogs/initial-review.sql"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$here/catalogs/dev-consent-documents.sql"

echo "seed complete"
