#!/usr/bin/env bash
# Assert the Apple app realizes its own declared schema: the LorvexCore resources
# it bundles must be byte-identical to the monorepo `schema/` authority the Apple
# app owns. This is an APPLE-ONLY integrity check — it never compares against
# `apps/tauri/...`. Apple and Tauri are only directionally aligned (shared
# concepts via `spec/`), not byte-locked, so the Tauri schema copy may diverge
# freely and is not consulted here.
#
# `schema/schema.sql` is the authority; the Apple app bundles
# `apps/apple/Sources/LorvexCore/Resources/schema.sql` (plus the migration ladder
# and `checksums.lock`) as LorvexCore resources so the production Swift core can
# apply the schema, stamp/verify the `schema_migrations` bookkeeping, and run the
# versioned-migration ladder with no env var or repo checkout. The bundled copies
# must not drift from the authority.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$APPLE_ROOT/../.." && pwd)"

SCHEMA_AUTHORITY="$REPO_ROOT/schema/schema.sql"
SCHEMA_APPLE_COPY="$APPLE_ROOT/Sources/LorvexCore/Resources/schema.sql"
LOCK_AUTHORITY="$REPO_ROOT/schema/migrations/checksums.lock"
LOCK_APPLE_COPY="$APPLE_ROOT/Sources/LorvexCore/Resources/checksums.lock"
MIGRATIONS_AUTHORITY_DIR="$REPO_ROOT/schema/migrations"
MIGRATIONS_APPLE_DIR="$APPLE_ROOT/Sources/LorvexCore/Resources/Migrations"

status=0

drift() {
  echo "$1" >&2
  status=1
}

if cmp -s "$SCHEMA_AUTHORITY" "$SCHEMA_APPLE_COPY"; then
  echo "schema embed OK: schema/schema.sql == apps/apple/.../LorvexCore/Resources/schema.sql"
else
  drift "SCHEMA DRIFT: the Apple bundled schema.sql differs from the authoritative schema/schema.sql."
fi

if cmp -s "$LOCK_AUTHORITY" "$LOCK_APPLE_COPY"; then
  echo "checksums embed OK: schema/migrations/checksums.lock == apps/apple/.../LorvexCore/Resources/checksums.lock"
else
  drift "CHECKSUM DRIFT: the Apple bundled checksums.lock differs from the canonical schema/migrations/checksums.lock."
fi

# Every canonical migration file (versions 002+; 001 is the baseline schema.sql)
# must have a byte-identical Apple embed.
migration_count=0
for canonical_file in "$MIGRATIONS_AUTHORITY_DIR"/[0-9][0-9][0-9]_*.sql; do
  [ -e "$canonical_file" ] || continue
  migration_count=$((migration_count + 1))
  name="$(basename "$canonical_file")"
  copy="$MIGRATIONS_APPLE_DIR/$name"
  if [ ! -f "$copy" ]; then
    drift "MIGRATION DRIFT: canonical migration $name has no Apple embed at $copy."
  elif ! cmp -s "$canonical_file" "$copy"; then
    drift "MIGRATION DRIFT: $copy differs from the canonical schema/migrations/$name."
  fi
done

# No Apple migration embed may exist without a canonical source (001_schema.sql
# is the baseline embed, covered by the schema.sql check above).
for copy in "$MIGRATIONS_APPLE_DIR"/[0-9][0-9][0-9]_*.sql; do
  [ -e "$copy" ] || continue
  name="$(basename "$copy")"
  [ "$name" = "001_schema.sql" ] && continue
  if [ ! -f "$MIGRATIONS_AUTHORITY_DIR/$name" ]; then
    drift "MIGRATION DRIFT: $copy has no canonical source at schema/migrations/$name."
  fi
done

if [ "$status" -ne 0 ]; then
  echo "Reconcile so the Apple embed matches the schema/ authority byte-for-byte." >&2
  exit 1
fi

echo "schema embed OK: Apple LorvexCore resources byte-identical to schema/ ($migration_count migration file(s))."
