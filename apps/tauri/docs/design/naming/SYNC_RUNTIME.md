# Sync and Runtime Naming

## Scope

This document defines naming for:

- entity types
- edge types
- outbox/inbox
- local runtime state
- authority
- lease ownership
- device identity
- audit stream naming

## Current State In Code

Observed in:

- `lorvex-domain/src/naming/`
- `lorvex-domain/src/preference_keys/`
- `lorvex-runtime/src/local_state/mod.rs`
- `lorvex-runtime/src/sync_owner/`
- `lorvex-runtime/src/mcp_authority.rs`
- `mcp-server/src/runtime/change_tracking/`
- app sync runtime code

Current code reality:

- canonical entity/edge/operation names already live in `lorvex-domain/src/naming/`
- runtime coordination uses:
  - `local_counters`
  - `local_sync_owner`
  - `local_change_seq`
  - `mcp_host_authority`
- sync transport uses:
  - `sync_outbox`
  - `sync_pending_inbox`
  - checkpoints
- `ai_changelog` is treated as audit stream, not source-of-truth aggregate

## Canonical Naming Groups

### Entity / Edge / Operation

These names are already canonical in code and should remain authoritative:

- entity names from `lorvex-domain/src/naming/`
- edge names from `lorvex-domain/src/naming/`
- operation names:
  - `upsert`
  - `delete`

Rule:

- do not introduce raw string literals for these names outside the canonical registry

### Transport

Canonical names:

- `sync_outbox`
- `sync_pending_inbox`
- `sync_checkpoint`
- `reseed`
- `apply`

Meaning:

- transport and replication coordination
- not source-of-truth data model

### Local Runtime Coordination

Canonical names:

- `local_counters`
- `local_change_seq`
- `local_sync_owner`
- `mcp_host_authority`

Meaning:

- same-machine coordination and local runtime truth

### Ownership vs Authority

These are different:

- `sync_owner`
  - who currently holds a backend sync lease
- `mcp_host_authority`
  - who should be the canonical external MCP host

These words must not be used interchangeably in docs or code comments.

### Identity

Canonical names:

- `device_id`
- `version`
- `hlc_version`
- `source_device_id`
- `initiated_by`
- `actor`

Meaning:

- identity and causality metadata

### Audit

Canonical internal name:

- `ai_changelog`

Meaning:

- append-only audit stream
- not an aggregate root
- not transport truth

Preferred UI label:

- `AI Activity`

## Preference and Device-State Keys

The codebase already has a good distinction:

- synced global preference keys:
  - `PREF_*`
- local device-state keys:
  - `DEV_*`

Rule:

- keep this distinction hard
- do not use `preference` and `device state` as interchangeable phrases

## Current Naming Risks

The main runtime naming risks still visible are:

- confusing authority and ownership
- using `sync` to mean both local visibility and remote replication
- describing `ai_changelog` as if it were either user-facing copy or transport truth
- using App/CLI installation wording without naming which runtime state actually governs external MCP authority

## Final Decision

The sync/runtime naming system should be treated as:

- canonical names come from `lorvex-domain/src/naming/`
- `sync_outbox` / `sync_pending_inbox` are transport-layer terms
- `local_change_seq` is local visibility coordination, not cloud sync
- `local_sync_owner` is lease ownership
- `mcp_host_authority` is external MCP authority
- `device_id` / `hlc_version` are identity/versioning terms
- `ai_changelog` is audit only, with `AI Activity` as the UI label
