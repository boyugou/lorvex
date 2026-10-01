-- iCloud sync runs on CKSyncEngine, which owns account identity, change
-- tokens, zone traversal, and record fetch retries. This migration removes the
-- local tables that tracked those for the custom transport, makes the audit
-- trail (`ai_changelog`) device-local with its retention policy in
-- `device_state`, and narrows `sync_outbox` to its two remaining dispositions.
-- Tombstones are kept indefinitely, so their cloud-confirmation stamp goes too.

-- 1. Outbox and pending-inbox rows that no longer have a meaning: audit
--    records never leave the device, and authoritative-adoption fences belong
--    to the retired snapshot flow.
DELETE FROM sync_outbox
WHERE entity_type = 'ai_changelog' OR disposition = 'authoritative_adoption';
DELETE FROM sync_pending_inbox WHERE envelope_entity_type = 'ai_changelog';

-- 2. Carry the user's audit retention policy into `device_state`. The active
--    account's policy wins; with no bound account the unbound candidate
--    applies. `maximum` is the absent-row default, so it is not stored.
INSERT INTO device_state (key, value)
SELECT 'ai_changelog_retention_policy', policy
FROM (
    SELECT CASE
        WHEN b.active_account_identifier IS NOT NULL THEN (
            SELECT s.policy_value FROM audit_retention_account_state s
            WHERE s.account_identifier = b.active_account_identifier
        )
        ELSE b.unbound_policy_value
    END AS policy
    FROM audit_retention_binding b
    LIMIT 1
)
WHERE policy IS NOT NULL AND policy <> '"maximum"'
ON CONFLICT(key) DO UPDATE SET value = excluded.value;

-- 3. Rebuild `sync_outbox` without the authoritative-session owner and the
--    future-record resolution policy. A future-record hold resolves by
--    last-writer-wins once a later build understands the held record.
CREATE TABLE sync_outbox_rebuilt (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type            TEXT NOT NULL,
    entity_id              TEXT NOT NULL,
    operation              TEXT NOT NULL
                           CHECK (operation IN ('upsert', 'delete')),
    version                TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    -- Decoded into UInt32 by the outbox read path; matches the nonzero wire
    -- domain at the storage boundary.
    payload_schema_version INTEGER NOT NULL
                           CHECK (payload_schema_version BETWEEN 1 AND 4294967295),
    payload                TEXT NOT NULL,
    -- Device-local provenance for a queued grouped-register upsert. The bits
    -- are interpreted by entity kind (calendar: content/topology; task:
    -- content/schedule/lifecycle/archive) and never serialized onto the wire.
    register_intent        INTEGER NOT NULL DEFAULT 0
                           CHECK (register_intent BETWEEN 0 AND 15),
    device_id              TEXT NOT NULL,
    created_at             TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    synced_at              TEXT,
    retry_count            INTEGER NOT NULL DEFAULT 0
                           CHECK (retry_count >= 0),
    last_retry_at          TEXT,
    -- The row's most recent push error; with the consecutive streak below it
    -- lets the retry loop recognize a permanent failure and escalate.
    last_error             TEXT,
    consecutive_error_count INTEGER NOT NULL DEFAULT 0
                            CHECK (consecutive_error_count >= 0
                                   AND consecutive_error_count <= retry_count),
    -- NULL is the ordinary active/synced state. `retry_wait` parks a failed
    -- push until `next_retry_at`, then it is re-armed automatically.
    -- `future_record_hold` preserves a local intent whose CloudKit identity is
    -- occupied by a record this build cannot understand; only a later
    -- understood envelope reconciles it.
    disposition            TEXT
                           CHECK (disposition IN ('retry_wait', 'future_record_hold')),
    -- Maximum HLC of the future-authored record(s) that fenced this intent.
    -- `version` remains the HLC of the preserved local intent itself.
    future_record_version  TEXT CHECK (
        future_record_version IS NULL
        OR (
            length(future_record_version) = 35
            AND substr(future_record_version, 14, 1) = '_'
            AND substr(future_record_version, 19, 1) = '_'
            AND substr(future_record_version, 1, 13) NOT GLOB '*[^0-9]*'
            AND substr(future_record_version, 15, 4) NOT GLOB '*[^0-9]*'
            AND substr(future_record_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
        )
    ),
    next_retry_at          TEXT,
    recovery_round         INTEGER NOT NULL DEFAULT 0
                           CHECK (recovery_round >= 0),
    CHECK (
        register_intent = 0
        OR (
            operation = 'upsert'
            AND (
                (entity_type = 'calendar_event' AND register_intent BETWEEN 1 AND 3)
                OR (entity_type = 'task' AND register_intent BETWEEN 1 AND 15)
            )
        )
    ),
    CHECK (
        (disposition IS NULL AND next_retry_at IS NULL AND future_record_version IS NULL)
        OR
        (disposition = 'retry_wait'
         AND synced_at IS NULL AND next_retry_at IS NOT NULL
         AND future_record_version IS NULL)
        OR
        (disposition = 'future_record_hold'
         AND synced_at IS NULL AND next_retry_at IS NULL
         AND future_record_version IS NOT NULL)
    )
) STRICT;

INSERT INTO sync_outbox_rebuilt (
    id, entity_type, entity_id, operation, version, payload_schema_version,
    payload, register_intent, device_id, created_at, synced_at, retry_count,
    last_retry_at, last_error, consecutive_error_count, disposition,
    future_record_version, next_retry_at, recovery_round
)
SELECT
    id, entity_type, entity_id, operation, version, payload_schema_version,
    payload, register_intent, device_id, created_at, synced_at, retry_count,
    last_retry_at, last_error, consecutive_error_count, disposition,
    future_record_version, next_retry_at, recovery_round
FROM sync_outbox
ORDER BY id;

-- Carry the AUTOINCREMENT high-water over, including ids of rows already
-- garbage-collected, so an outbox id is never reused.
DELETE FROM sqlite_sequence WHERE name = 'sync_outbox_rebuilt';
INSERT INTO sqlite_sequence (name, seq)
SELECT 'sync_outbox_rebuilt', seq FROM sqlite_sequence WHERE name = 'sync_outbox';

DROP TABLE sync_outbox;
ALTER TABLE sync_outbox_rebuilt RENAME TO sync_outbox;

-- Active FIFO queue: `WHERE synced_at IS NULL AND disposition IS NULL AND
-- retry_count < ? ORDER BY id`, answered from the index alone.
CREATE INDEX idx_sync_outbox_pending
    ON sync_outbox(id, retry_count)
    WHERE synced_at IS NULL AND disposition IS NULL;
CREATE INDEX idx_sync_outbox_retry_due
    ON sync_outbox(next_retry_at, id)
    WHERE synced_at IS NULL AND disposition = 'retry_wait';
CREATE INDEX idx_sync_outbox_future_hold_identity
    ON sync_outbox(entity_type, entity_id, future_record_version)
    WHERE synced_at IS NULL AND disposition = 'future_record_hold';
CREATE INDEX idx_sync_outbox_entity ON sync_outbox(entity_type, entity_id);
-- At most one unsynced row per entity, so concurrent writers (the app, the MCP
-- host, extensions) cannot both pass the coalescing SELECT and insert twice.
CREATE UNIQUE INDEX idx_sync_outbox_unsynced_per_entity
    ON sync_outbox(entity_type, entity_id) WHERE synced_at IS NULL;
-- Serves the synced-history GC, which the unsynced partial indexes exclude.
CREATE INDEX idx_sync_outbox_synced_at
    ON sync_outbox(synced_at) WHERE synced_at IS NOT NULL;

-- 4. Retired transport and audit-retention state, dropped child-first so no
--    foreign key ever points at a missing parent.
DROP INDEX IF EXISTS idx_ai_changelog_retention_scope;
DROP INDEX IF EXISTS idx_audit_retention_purge_pending;
DROP INDEX IF EXISTS idx_audit_changelog_presence_entity;
DROP INDEX IF EXISTS idx_generation_snapshot_readback_audit;

DROP TABLE sync_generation_snapshot_readback_items;
DROP TABLE sync_generation_snapshot_items;
DROP TABLE sync_generation_snapshot_tombstone_receipts;
DROP TABLE sync_generation_snapshot_compacted_tombstones;
DROP TABLE sync_generation_snapshot_staging;
DROP TABLE sync_authoritative_snapshot_records;
DROP TABLE sync_authoritative_snapshot;
DROP TABLE sync_cloudkit_corrupt_record_fences;
DROP TABLE sync_cloudkit_incremental_cursor;
DROP TABLE sync_cloudkit_traversal_witness;
DROP TABLE sync_cloudkit_traversal_progress;
DROP TABLE sync_cloudkit_generation_descriptor;
DROP TABLE sync_cloudkit_authority_witness;
DROP TABLE sync_cloudkit_account_binding;

DROP TABLE audit_retention_purge_queue;
DROP TABLE audit_changelog_cloud_presence;
DROP TABLE audit_retention_candidate_authorization;
DROP TABLE audit_retention_outbound_authorization;
DROP TABLE audit_retention_account_state;
DROP TABLE audit_retention_binding;

-- 5. Columns that only served the retired pieces. `ai_changelog` is rebuilt
--    rather than altered: SQLite's DROP COLUMN rewrite cannot cope with the
--    baseline's comment between its retention columns. Its child table is
--    rebuilt against the new parent first, because dropping a parent with
--    foreign keys on cascades into its children.
CREATE TABLE ai_changelog_rebuilt (
    id               TEXT PRIMARY KEY,
    timestamp        TEXT NOT NULL
                     CHECK (length(timestamp) > 0),
    operation        TEXT NOT NULL
                     CHECK (
                         length(operation) > 0
                         AND operation = trim(operation)
                     ),
    entity_type      TEXT NOT NULL
                     CHECK (
                         length(entity_type) > 0
                         AND entity_type = trim(entity_type)
                     ),
    entity_id        TEXT,
    summary          TEXT NOT NULL,
    initiated_by     TEXT NOT NULL DEFAULT 'ai'
                     CHECK (
                         length(initiated_by) > 0
                         AND initiated_by = trim(initiated_by)
                     ),
    mcp_tool         TEXT,
    source_device_id TEXT,
    -- Structured before/after JSON snapshots for update operations; NULL when
    -- an operation captures no state transition. Each is valid JSON capped at
    -- 4000 bytes; an over-budget state becomes a structured truncation
    -- sentinel with a bounded preview.
    before_json      TEXT CHECK (before_json IS NULL OR json_valid(before_json)),
    after_json       TEXT CHECK (after_json IS NULL OR json_valid(after_json))
) STRICT;

INSERT INTO ai_changelog_rebuilt (
    id, timestamp, operation, entity_type, entity_id, summary, initiated_by,
    mcp_tool, source_device_id, before_json, after_json
)
SELECT
    id, timestamp, operation, entity_type, entity_id, summary, initiated_by,
    mcp_tool, source_device_id, before_json, after_json
FROM ai_changelog;

-- One row per entity a changelog entry touched; the PK serves the
-- per-entity lookup and the secondary index the per-entry join.
CREATE TABLE ai_changelog_entities_rebuilt (
    changelog_id TEXT NOT NULL REFERENCES ai_changelog_rebuilt(id) ON DELETE CASCADE,
    entity_id    TEXT NOT NULL,
    PRIMARY KEY (entity_id, changelog_id)
) STRICT;

INSERT INTO ai_changelog_entities_rebuilt (changelog_id, entity_id)
SELECT changelog_id, entity_id FROM ai_changelog_entities;

DROP TABLE ai_changelog_entities;
DROP TABLE ai_changelog;
-- Renaming the parent rewrites the child's foreign key to the final name.
ALTER TABLE ai_changelog_rebuilt RENAME TO ai_changelog;
ALTER TABLE ai_changelog_entities_rebuilt RENAME TO ai_changelog_entities;

-- Timestamp order breaks same-millisecond ties by id, so polling on
-- `timestamp > ?` never drops a row.
CREATE INDEX idx_changelog_timestamp ON ai_changelog(timestamp DESC, id DESC);
CREATE INDEX idx_changelog_entity ON ai_changelog(entity_type, entity_id);
CREATE INDEX idx_changelog_operation ON ai_changelog(operation);
CREATE INDEX idx_ai_changelog_entities_changelog
    ON ai_changelog_entities(changelog_id);

ALTER TABLE sync_tombstones DROP COLUMN cloud_confirmed_at;

-- 6. Checkpoint keys written only by the retired transport.
DELETE FROM sync_checkpoints
WHERE key IN (
    'cloudkit_per_record_fetch_failure_checkpoint',
    'cloudkit_per_record_fetch_failure_count'
)
OR key LIKE 'enrolled\_zone\_epoch.%' ESCAPE '\';
