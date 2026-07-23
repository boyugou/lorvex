# Lorvex SQLite schema

This directory embeds the schema artifacts the Rust runtime compiles in:

* `001_schema.sql` — the consolidated baseline (schema version 1), tracking the
  monorepo `schema/schema.sql`. The Apple app owns that schema authority; this
  Tauri copy is only directionally aligned via `spec/`, not byte-locked, so the
  monorepo no longer enforces byte-equality against it and it may diverge.
* `NNN_<name>.sql` (versions 002+) — post-launch migrations tracking the
  canonical `schema/migrations/NNN_<name>.sql` at the monorepo root (again,
  directionally aligned, not byte-locked). Each copy is registered in
  `ladder_migrations()` (`mod.rs`) via `include_str!`. There are none while
  `schema/migration_policy.json` has `launched: false` — pre-launch, the schema
  evolves by editing the baseline directly, never by adding migrations.
* `checksums.lock` — the normalized SHA-256 of every entry above, a
  byte-identical copy of the canonical `schema/migrations/checksums.lock`.
  Both the CI verifier (`scripts/verify/migration_checksums.mjs`) and the
  runtime (`schema::enforce_embedded_lock_checksums`, called from
  `apply_migrations`) refuse to proceed when any embedded SQL disagrees with
  its recorded hash. Regenerate with
  `node scripts/verify/migration_checksums.mjs --seed` after an intentional
  pre-launch baseline edit, then mirror the lock byte-identically to
  `schema/migrations/checksums.lock` and the Apple copy.

## Rules

* The monorepo `schema/` tree is the source of truth for every file here;
  nothing in this directory is edited independently.
* Pre-launch (`launched: false`): edit `schema/schema.sql` (and this copy)
  directly, re-seed `checksums.lock`, keep the ladder empty.
* Post-launch (`launched: true`): the baseline and every released lock entry
  are frozen forever. A schema change is a new canonical
  `schema/migrations/NNN_<name>.sql`, copied here and appended to
  `ladder_migrations()`; its lock entry is appended, never re-seeded. The full
  contract — numbering, checksum normalization, SQL dialect constraints — is
  `schema/migrations/README.md` at the monorepo root.
