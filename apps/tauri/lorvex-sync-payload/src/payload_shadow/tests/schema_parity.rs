//! Schema parity: every synced SQL column must have a corresponding
//! entry in `owned_keys_for_entity`, and every allowlist entry must be
//! grounded in the schema (or declared as a synthetic rollup key).
//! This is the forcing function that catches drift between the SQL
//! schema and the payload-shadow allowlist.

use super::support::*;

/// the `owned_keys_for_entity` allowlist is the contract
/// that `merge_payload_with_shadow` uses to decide which keys in a
/// preserved-shadow payload are "owned by this version" and may be
/// dropped when absent from the freshly-enqueued payload, versus
/// "unknown — preserve across re-echo" (the forward-compat escape
/// hatch that survives a peer running a newer schema).
///
/// Any column that lives in the SQL schema but is missing from the
/// allowlist is a silent re-echo loss waiting to happen: the enqueue
/// snapshot in `lorvex-sync::outbox_enqueue::read_entity_snapshot`
/// reads the column via `pragma_table_info` and emits it into the
/// payload, a peer at the same version parses and persists it, and
/// then a downgrade re-echo from an older peer (that never wrote the
/// column) replaces the shadow with a payload that has no entry for
/// the column — and since the key is not in `owned_keys_for_entity`,
/// the merge path treats the shadow's prior value as "unknown" and
/// preserves it indefinitely. Same failure class as #2229 (downgrade
/// overwrite), except here the drift is between the two
/// hand-maintained lists ("schema columns" and "owned keys") instead
/// of between shadow and apply.
///
/// This test is the forcing function: adding a column to a synced
/// table now requires updating the allowlist in the same commit, or
/// `cargo test -p lorvex-store --lib` fails.
#[test]
fn payload_shadow_schema_parity() {
    use std::collections::{BTreeMap, BTreeSet};

    // entity_type → SQL table name. Mirrors
    // `entity_type_to_table` in `lorvex-sync::outbox_enqueue` for
    // synced entity types, extended with the two entity types that
    // route through bespoke enqueue paths (edges, ai_changelog).
    // Every entry in this map MUST have a corresponding arm in
    // `owned_keys_for_entity`; the second assertion below proves it.
    let entity_to_table: BTreeMap<&str, &str> = BTreeMap::from([
        // Aggregate roots
        (ENTITY_TASK, "tasks"),
        (ENTITY_LIST, "lists"),
        (ENTITY_HABIT, "habits"),
        (ENTITY_TAG, "tags"),
        (ENTITY_CALENDAR_EVENT, "calendar_events"),
        (ENTITY_PREFERENCE, "preferences"),
        (ENTITY_MEMORY, "memories"),
        (ENTITY_MEMORY_REVISION, "memory_revisions"),
        (ENTITY_DAILY_REVIEW, "daily_reviews"),
        (ENTITY_CURRENT_FOCUS, "current_focus"),
        (ENTITY_FOCUS_SCHEDULE, "focus_schedule"),
        (ENTITY_CALENDAR_SUBSCRIPTION, "calendar_subscriptions"),
        // Independent children
        (ENTITY_TASK_REMINDER, "task_reminders"),
        (ENTITY_TASK_CHECKLIST_ITEM, "task_checklist_items"),
        (ENTITY_HABIT_REMINDER_POLICY, "habit_reminder_policies"),
        // Append-only audit log
        (ENTITY_AI_CHANGELOG, "ai_changelog"),
        // Relation edges (synced, composite natural key)
        (EDGE_TASK_TAG, "task_tags"),
        (EDGE_TASK_DEPENDENCY, "task_dependencies"),
        (EDGE_TASK_CALENDAR_EVENT_LINK, "task_calendar_event_links"),
        (EDGE_HABIT_COMPLETION, "habit_completions"),
    ]);

    // Columns that live in the schema but legitimately do NOT
    // belong in the owned_keys allowlist, per entity_type. Each
    // entry must be justified — a bare addition here silently
    // regresses the parity guarantee. Keep the rationale inline
    // so a future reader can audit every exception.
    let schema_only_exceptions: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::from([
        (
            ENTITY_TASK,
            BTreeSet::from([
                // Virtual generated column (`COALESCE(priority, 4)
                // VIRTUAL`, migration 009). Derived on read; never
                // carried in payloads and re-derived on apply.
                "priority_effective",
            ]),
        ),
        (
            ENTITY_CALENDAR_EVENT,
            BTreeSet::from([
                // #2824: derived UNTIL bound. STORED generated column
                // computed from `json_extract(recurrence, '$.UNTIL')` —
                // never carried in payloads (it's a pure function of
                // `recurrence`, which IS in the allowlist) and re-
                // derived on apply by the receiving peer's own
                // generated column, so sync remains a no-op here.
                "recurrence_end_date",
            ]),
        ),
    ]);

    // Synthetic fields that live ONLY in the payload (never in
    // the schema) — the aggregate's materialized-children rollup.
    // These are legitimate entries in the allowlist because the
    // apply pipeline rebuilds the relevant child table from them;
    // the parity check must tolerate their absence from
    // `pragma_table_info`.
    let payload_only_synthetics: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::from([
        (
            ENTITY_CALENDAR_EVENT,
            BTreeSet::from([
                "attendees", // → calendar_event_attendees
                // EXDATE list moved to
                // `calendar_event_recurrence_exceptions` (#4585).
                // The payload still carries the wire-form JSON
                // array; the column no longer exists on
                // `calendar_events` itself.
                "recurrence_exceptions",
            ]),
        ),
        (
            ENTITY_CURRENT_FOCUS,
            BTreeSet::from(["task_ids"]), // → current_focus_items
        ),
        (
            ENTITY_FOCUS_SCHEDULE,
            BTreeSet::from(["blocks"]), // → focus_schedule_blocks
        ),
        (
            ENTITY_DAILY_REVIEW,
            BTreeSet::from([
                "linked_task_ids", // → daily_review_task_links
                "linked_list_ids", // → daily_review_list_links
            ]),
        ),
        // declare `checklist_items` as a known
        // synthetic for ENTITY_TASK. The aggregate's checklist
        // rollup lives in the `task_checklist_items` child
        // table (a separately-synced entity) and is only
        // re-materialized into the task payload when an
        // enrichment pass runs — every other layer of the
        // shadow ↔ payload contract treats checklist data as
        // child rows. Listing the key here pre-emptively keeps
        // the parity test honest: the moment a future change
        // adds `checklist_items` to `owned_keys_for_entity`
        // (e.g. an aggregate-payload format that ships an
        // inline rollup) the test stops silently failing
        // closed and instead validates the synthetic
        // declaration.
        (
            ENTITY_TASK,
            BTreeSet::from([
                "checklist_items", // → task_checklist_items
                // EXDATE list moved to
                // `task_recurrence_exceptions` (#4585). The
                // payload still carries the wire-form JSON
                // array (built via `json_group_array` on read,
                // replaced into the child table on apply) so
                // the owned-keys allowlist keeps the field
                // even though `pragma_table_info('tasks')` no
                // longer lists it.
                "recurrence_exceptions",
            ]),
        ),
        (
            ENTITY_AI_CHANGELOG,
            BTreeSet::from([
                // Batch/bulk entity-id registry moved to
                // `ai_changelog_entities` (#4613). The wire
                // payload still carries the JSON-array field —
                // built via `json_group_array` on read, replayed
                // into the child table on apply — so the
                // owned-keys allowlist keeps `entity_ids` even
                // though `pragma_table_info('ai_changelog')` no
                // longer lists the column.
                "entity_ids",
            ]),
        ),
        (
            ENTITY_HABIT,
            // The `weekly` weekday set lives in the `habit_weekdays`
            // child. The payload carries the Monday-first integer array —
            // built via `json_group_array` on read, rebuilt into the child
            // table on apply — so the owned-keys allowlist keeps `weekdays`
            // even though `pragma_table_info('habits')` never lists it.
            BTreeSet::from(["weekdays"]),
        ),
    ]);

    let conn = open_db_in_memory().unwrap();

    let mut failures: Vec<String> = Vec::new();
    for (entity_type, table) in &entity_to_table {
        // even though this is a test with hardcoded
        // table names, co-locate the identifier guard with the
        // `format!` interpolation so a future test edit that pulls
        // the table name from runtime input (env var, fixture file)
        // cannot accidentally introduce a SQLi sink in test code
        // that runs against developer machines and CI databases.
        lorvex_domain::assert_safe_sql_identifier(table);
        let sql = format!("SELECT name FROM pragma_table_info('{table}') ORDER BY cid");
        let mut stmt = conn.prepare(&sql).unwrap();
        let schema_cols: BTreeSet<String> = stmt
            .query_map([], |row| row.get::<_, String>(0))
            .unwrap()
            .collect::<Result<BTreeSet<_>, _>>()
            .unwrap();
        assert!(
            !schema_cols.is_empty(),
            "table {table} for entity_type {entity_type} has no columns — \
             schema or mapping is broken",
        );

        let owned: BTreeSet<&str> = owned_keys_for_entity(entity_type).iter().copied().collect();
        assert!(
            !owned.is_empty(),
            "owned_keys_for_entity({entity_type}) returned empty — \
             every entity_type in entity_to_table must have an arm",
        );

        let empty = BTreeSet::new();
        let exceptions = schema_only_exceptions.get(entity_type).unwrap_or(&empty);
        let synthetics = payload_only_synthetics.get(entity_type).unwrap_or(&empty);

        // Schema columns missing from owned_keys (and not excepted)
        // — the dangerous drift class. A peer emits them on re-echo
        // but the merge path treats them as unowned and preserves
        // stale shadow values indefinitely.
        let schema_not_owned: Vec<&str> = schema_cols
            .iter()
            .map(String::as_str)
            .filter(|c| !owned.contains(c) && !exceptions.contains(c))
            .collect();
        if !schema_not_owned.is_empty() {
            failures.push(format!(
                "{entity_type} (table {table}): schema columns missing from \
                 owned_keys_for_entity: {schema_not_owned:?} — add them to the \
                 allowlist or to schema_only_exceptions with a rationale",
            ));
        }

        // Allowlist entries missing from the schema (and not a
        // known synthetic rollup key). Lower risk, but a stale
        // entry misreports ownership in the diagnostics panel and
        // hides real drift — fail the same way.
        let owned_not_schema: Vec<&str> = owned
            .iter()
            .copied()
            .filter(|c| !schema_cols.contains(*c) && !synthetics.contains(c))
            .collect();
        if !owned_not_schema.is_empty() {
            failures.push(format!(
                "{entity_type} (table {table}): owned_keys entries missing from \
                 schema: {owned_not_schema:?} — drop them from the allowlist or \
                 declare them in payload_only_synthetics with a rationale",
            ));
        }
    }

    assert!(
        failures.is_empty(),
        "owned_keys_for_entity ↔ schema parity check failed:\n  - {}",
        failures.join("\n  - "),
    );
}
