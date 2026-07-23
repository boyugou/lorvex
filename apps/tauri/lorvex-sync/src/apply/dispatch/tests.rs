use lorvex_domain::naming;

use super::handler::ENTITY_HANDLERS;

/// Drift guard: every entity_type listed in
/// `naming::ALL_SYNCABLE_TYPES` must have a registered handler.
/// Adding a new sync entity that forgets to wire a handler will
/// fail this test instead of falling through to
/// `UnknownEntityType` at runtime on a peer's apply path.
#[test]
fn every_syncable_entity_has_a_dispatch_handler() {
    let registered: std::collections::HashSet<&str> =
        ENTITY_HANDLERS.iter().map(|(et, _)| *et).collect();
    for entity_type in naming::ALL_SYNCABLE_TYPES {
        assert!(
            registered.contains(entity_type),
            "{entity_type} is in naming::ALL_SYNCABLE_TYPES but has no \
             dispatch handler — sync envelopes for this type will fail \
             with UnknownEntityType on every peer's apply path"
        );
    }
}

/// Drift guard in the other direction: no entity type is
/// registered twice. A duplicate would cause the linear-scan
/// `find` to dispatch to the first registration and silently
/// ignore the second.
#[test]
fn dispatch_table_has_no_duplicate_entity_types() {
    let mut seen = std::collections::HashSet::new();
    for (entity_type, _) in ENTITY_HANDLERS {
        assert!(
            seen.insert(*entity_type),
            "{entity_type} is registered more than once in ENTITY_HANDLERS"
        );
    }
}

/// drift guard for the natural-key day-scoped
/// aggregates (`current_focus`, `focus_schedule`, `daily_reviews`).
/// The post-handler LWW-rejection check at lines 643-657 of this
/// module calls `super::get_local_version(conn, entity_type, id)`
/// and compares the post-handler version against the envelope's.
/// For day-scoped tables the `id` parameter is the `date` natural
/// key, NOT a UUIDv7 — so `get_local_version` MUST resolve the
/// row via `WHERE date = ?1` rather than `WHERE id = ?1`. A
/// regression to `id = ?1` here would silently make the
/// post-handler check return `None` for every day-scoped delete
/// (the `id` column does not exist on these tables), defeating
/// the LWW-rejected branch and durably overriding cluster-known
/// surviving rows on the next re-sync.
///
/// We seed each table with a row at a known version, then assert
/// that `get_local_version(conn, "current_focus", date)` returns
/// that version. A future refactor that switches the lookup back
/// to `id = ?1` would fail here because the day-scoped tables
/// have no `id` column at all — the `prepare_cached` would error
/// at SQL parse time.
#[test]
fn get_local_version_resolves_day_scoped_aggregates_by_date() {
    use rusqlite::params;

    let conn = crate::test_db();
    let date = "2026-04-28";
    let v_current = "1711234567890_0000_a1b2c3d4a1b2c3d4";
    let v_schedule = "1711234567891_0000_a1b2c3d4a1b2c3d4";
    let v_review = "1711234567892_0000_a1b2c3d4a1b2c3d4";

    // current_focus: PK = date.
    conn.execute(
        "INSERT INTO current_focus (date, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?3)",
        params![date, v_current, "2026-04-28T00:00:00.000Z"],
    )
    .unwrap();

    // focus_schedule: PK = date.
    conn.execute(
        "INSERT INTO focus_schedule (date, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?3)",
        params![date, v_schedule, "2026-04-28T00:00:00.000Z"],
    )
    .unwrap();

    // daily_reviews: PK = date.
    conn.execute(
        "INSERT INTO daily_reviews (date, summary, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?4)",
        params![
            date,
            "drift-guard summary",
            v_review,
            "2026-04-28T00:00:00.000Z"
        ],
    )
    .unwrap();

    // The natural-key lookup MUST find each row via the date
    // string passed as `entity_id`. A regression to `id = ?` would
    // either error at SQL parse time (no `id` column) or return
    // None (no match), both of which fail this assertion.
    assert_eq!(
        super::super::get_local_version(
            &conn,
            lorvex_domain::naming::EntityKind::CurrentFocus.as_str(),
            date,
        )
        .unwrap()
        .as_deref(),
        Some(v_current),
        "get_local_version must resolve current_focus by date natural key"
    );
    assert_eq!(
        super::super::get_local_version(
            &conn,
            lorvex_domain::naming::EntityKind::FocusSchedule.as_str(),
            date,
        )
        .unwrap()
        .as_deref(),
        Some(v_schedule),
        "get_local_version must resolve focus_schedule by date natural key"
    );
    assert_eq!(
        super::super::get_local_version(
            &conn,
            lorvex_domain::naming::EntityKind::DailyReview.as_str(),
            date,
        )
        .unwrap()
        .as_deref(),
        Some(v_review),
        "get_local_version must resolve daily_reviews by date natural key"
    );

    // Negative case: a date that's NOT seeded must return None,
    // confirming the lookup actually filters on date rather than
    // returning any row in the table.
    assert!(
        super::super::get_local_version(
            &conn,
            lorvex_domain::naming::EntityKind::CurrentFocus.as_str(),
            "1999-01-01",
        )
        .unwrap()
        .is_none(),
        "get_local_version must return None for an unmatched date"
    );
}
