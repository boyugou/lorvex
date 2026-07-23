//! Per-event attendee sub-table materialization.
//!
//! Owns the DELETE+INSERT replace-set semantics for
//! `calendar_event_attendees` plus the per-row hygiene checks (NFC +
//! length cap, no whitespace / control codes in the email). Every
//! surface that writes a calendar event — MCP, CLI, Tauri app IPC,
//! sync apply — routes through this single function so non-canonical
//! PARTSTAT spellings, half-cleared lists, and runaway-length fields
//! all stop here.

use lorvex_domain::validation::MAX_SHORT_TEXT_LENGTH;
use lorvex_domain::{sanitize_user_text, AttendeeStatus, EventId};
use rusqlite::{params, Connection};

use super::{AttendeeShadowInput, CalendarEventOpError};

/// Replace the attendee sub-table rows for `event_id` with the
/// supplied list. Validates each entry's hygiene (NFC + length cap,
/// no whitespace / control codes in the email) and accepts the
/// [`AttendeeStatus`] enum directly so non-canonical PARTSTAT
/// spellings cannot reach the row.
///
/// This is the canonical attendee materializer every surface
/// shares — calendar event mutations across MCP, app IPC, CLI, and
/// sync apply all route through this single function.
pub fn materialize_attendees(
    conn: &Connection,
    event_id: &EventId,
    attendees: &[AttendeeShadowInput],
) -> Result<(), CalendarEventOpError> {
    // Every consumer surface wraps the materialization in an outer
    // savepoint / immediate transaction (the calendar event mutation
    // executor on every surface, plus the sync apply path). The
    // DELETE+INSERT pair must run atomically — if a partial INSERT
    // fails after the DELETE without an enclosing rollback boundary,
    // the row's attendees would be silently dropped. Assert in debug
    // builds so a future caller bypassing the executor surfaces
    // the violation immediately.
    debug_assert!(
        !conn.is_autocommit(),
        "materialize_attendees must run inside an active transaction or savepoint",
    );

    // Validate every insert row BEFORE issuing the DELETE so a
    // validation error never leaves the row's attendee list cleared
    // with no replacement.
    // mid-loop validation error relied on the outer savepoint to roll
    // back — correct today but fragile to refactors that flatten the
    // savepoint scope.
    let mut prepared: Vec<(String, String, Option<String>, Option<&'static str>)> =
        Vec::with_capacity(attendees.len());
    // Track synthesized `attendee_id`s to reject duplicate identities at
    // validation time instead of letting the INSERT OR REPLACE silently
    // coalesce two rows keyed by (event_id, attendee_id). Two attendees
    // that collapse to the same identity (same email, or same name with an
    // empty email) drop one entry otherwise, with no diagnostic.
    let mut seen_ids: std::collections::HashSet<String> =
        std::collections::HashSet::with_capacity(attendees.len());
    for attendee in attendees {
        let email_sanitized = sanitize_user_text(&attendee.email);
        let email = email_sanitized.trim().to_lowercase();
        // Email is OPTIONAL: a name-only attendee materializes under a
        // name-derived identity rather than dropping the whole event.
        // Shape checks apply only when an email is actually present.
        if !email.is_empty() {
            if email.chars().count() > MAX_SHORT_TEXT_LENGTH {
                return Err(CalendarEventOpError::Validation(format!(
                    "attendee email exceeds maximum length of {MAX_SHORT_TEXT_LENGTH}"
                )));
            }
            if email.chars().any(|c| c.is_whitespace() || c.is_control()) {
                return Err(CalendarEventOpError::Validation(format!(
                    "attendee email '{}' contains whitespace or control characters",
                    attendee.email
                )));
            }
        }

        let name = attendee
            .name
            .as_deref()
            .map(sanitize_user_text)
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());
        if let Some(ref name_value) = name {
            if name_value.chars().count() > MAX_SHORT_TEXT_LENGTH {
                return Err(CalendarEventOpError::Validation(format!(
                    "attendee name exceeds maximum length of {MAX_SHORT_TEXT_LENGTH}"
                )));
            }
        }

        // A fully anonymous attendee (no email AND no name) carries nothing
        // but its content to key on. The untrusted sync-apply path keeps it
        // via `AttendeeIdentity`'s content-hash fallback (peer data must
        // never drop the whole event), but this trusted local write surface
        // rejects it rather than admit a contentless attendee. Every row
        // reaching the synthesize call below therefore has an email or a
        // name, so the anonymous `canonicalJSON` fallback is never evaluated
        // (hence the empty-string basis).
        if email.is_empty() && name.is_none() {
            return Err(CalendarEventOpError::Validation(
                "attendee must carry an email or a name".to_string(),
            ));
        }

        let attendee_id = lorvex_domain::attendee_identity::synthesize(&email, name.as_deref(), "");
        if !seen_ids.insert(attendee_id.clone()) {
            let label = if email.is_empty() {
                name.clone().unwrap_or_default()
            } else {
                email.clone()
            };
            return Err(CalendarEventOpError::Validation(format!(
                "duplicate attendee '{label}' in payload; \
                 each attendee identity may appear at most once per event"
            )));
        }

        let status: Option<&'static str> = attendee.status.map(AttendeeStatus::as_str);
        prepared.push((attendee_id, email, name, status));
    }

    conn.execute(
        "DELETE FROM calendar_event_attendees WHERE event_id = ?",
        params![event_id.as_str()],
    )?;
    if prepared.is_empty() {
        return Ok(());
    }
    let mut stmt = conn.prepare_cached(
        "INSERT OR REPLACE INTO calendar_event_attendees (event_id, attendee_id, email, name, status) \
         VALUES (?1, ?2, ?3, ?4, ?5)",
    )?;
    for (attendee_id, email, name, status) in &prepared {
        stmt.execute(params![event_id.as_str(), attendee_id, email, name, status])?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use lorvex_store::test_support::test_conn;
    use rusqlite::params;

    fn seed_event(conn: &rusqlite::Connection, id: &str) {
        conn.execute(
            "INSERT INTO calendar_events
                (id, title, start_date, all_day, version, created_at, updated_at, event_type)
             VALUES (?1, 'Standup', '2026-04-20', 1,
                     '0000000000000_0000_seedcalseedcalse',
                     '2026-04-19T08:00:00Z', '2026-04-19T08:00:00Z', 'event')",
            params![id],
        )
        .expect("seed event");
    }

    ///  B21: a payload carrying the same normalized email twice
    /// (different name capitalization, different status) must be
    /// rejected at validation time.
    /// `INSERT OR REPLACE` keyed by (event_id, email) silently
    /// coalesced the two rows, dropping the first entry without the
    /// caller noticing.
    #[test]
    fn duplicate_attendee_email_is_rejected_at_validation() {
        let conn = test_conn();
        seed_event(&conn, "evt-dup-a");
        let event_id = EventId::from_trusted("evt-dup-a".to_string());

        let tx = conn.unchecked_transaction().expect("begin tx");
        let err = materialize_attendees(
            &tx,
            &event_id,
            &[
                AttendeeShadowInput {
                    email: "alice@example.com".to_string(),
                    name: Some("Alice".to_string()),
                    status: Some(AttendeeStatus::Accepted),
                },
                AttendeeShadowInput {
                    email: "alice@example.com".to_string(),
                    name: Some("Alice (work)".to_string()),
                    status: Some(AttendeeStatus::Tentative),
                },
            ],
        )
        .expect_err("duplicate emails must reject");
        match err {
            CalendarEventOpError::Validation(msg) => {
                assert!(
                    msg.contains("duplicate") && msg.contains("alice@example.com"),
                    "error must mention duplicate + the offending email; got {msg}",
                );
            }
            other => panic!("expected Validation error, got {other:?}"),
        }
        tx.rollback().expect("rollback after rejected validation");
    }

    /// Case-folding and whitespace are normalized before the
    /// duplicate check, so `Alice@example.com ` and
    /// `alice@example.com` still trip the validation guard rather
    /// than slipping past it as distinct strings.
    #[test]
    fn duplicate_check_runs_after_email_normalization() {
        let conn = test_conn();
        seed_event(&conn, "evt-dup-b");
        let event_id = EventId::from_trusted("evt-dup-b".to_string());

        let tx = conn.unchecked_transaction().expect("begin tx");
        let err = materialize_attendees(
            &tx,
            &event_id,
            &[
                AttendeeShadowInput {
                    email: "Alice@Example.com".to_string(),
                    name: Some("Alice".to_string()),
                    status: None,
                },
                AttendeeShadowInput {
                    email: "  alice@example.com  ".to_string(),
                    name: Some("Alice 2".to_string()),
                    status: None,
                },
            ],
        )
        .expect_err("normalization-equivalent emails must reject");
        assert!(matches!(err, CalendarEventOpError::Validation(_)));
        tx.rollback().expect("rollback after rejected validation");
    }

    /// A name-only attendee (email collapses to empty, but a display name is
    /// present) materializes under a `name:`-derived identity rather than
    /// being dropped — matching Apple's `CalendarEventAttendees`.
    #[test]
    fn name_only_attendee_materializes_under_name_identity() {
        let conn = test_conn();
        seed_event(&conn, "evt-name-only");
        let event_id = EventId::from_trusted("evt-name-only".to_string());

        let tx = conn.unchecked_transaction().expect("begin tx");
        materialize_attendees(
            &tx,
            &event_id,
            &[AttendeeShadowInput {
                email: "   ".to_string(),
                name: Some("Anon".to_string()),
                status: Some(AttendeeStatus::Accepted),
            }],
        )
        .expect("name-only attendee must materialize");
        let attendee_id: String = tx
            .query_row(
                "SELECT attendee_id FROM calendar_event_attendees WHERE event_id = ?1",
                params!["evt-name-only"],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(attendee_id, "name:anon");
        tx.commit().expect("commit");
    }

    /// A fully anonymous attendee (empty email AND no name) has no content to
    /// key on and is rejected at this trusted local write surface.
    #[test]
    fn fully_anonymous_attendee_is_rejected_at_validation() {
        let conn = test_conn();
        seed_event(&conn, "evt-anon");
        let event_id = EventId::from_trusted("evt-anon".to_string());

        let tx = conn.unchecked_transaction().expect("begin tx");
        let err = materialize_attendees(
            &tx,
            &event_id,
            &[AttendeeShadowInput {
                email: "   ".to_string(),
                name: None,
                status: Some(AttendeeStatus::Accepted),
            }],
        )
        .expect_err("fully anonymous attendee must reject");
        match err {
            CalendarEventOpError::Validation(msg) => {
                assert!(
                    msg.contains("email or a name"),
                    "error must explain the email-or-name requirement; got {msg}",
                );
            }
            other => panic!("expected Validation error, got {other:?}"),
        }
        tx.rollback().expect("rollback after rejected validation");
    }

    /// Distinct emails on the same event still materialize cleanly —
    /// the duplicate guard is keyed on `(event_id, normalized_email)`
    /// equality, not on the row count.
    #[test]
    fn distinct_attendees_materialize_without_duplicate_error() {
        let conn = test_conn();
        seed_event(&conn, "evt-dup-c");
        let event_id = EventId::from_trusted("evt-dup-c".to_string());

        let tx = conn.unchecked_transaction().expect("begin tx");
        materialize_attendees(
            &tx,
            &event_id,
            &[
                AttendeeShadowInput {
                    email: "alice@example.com".to_string(),
                    name: Some("Alice".to_string()),
                    status: Some(AttendeeStatus::Accepted),
                },
                AttendeeShadowInput {
                    email: "bob@example.com".to_string(),
                    name: Some("Bob".to_string()),
                    status: Some(AttendeeStatus::Declined),
                },
            ],
        )
        .expect("distinct attendees must materialize");
        let count: i64 = tx
            .query_row(
                "SELECT COUNT(*) FROM calendar_event_attendees WHERE event_id = ?1",
                params!["evt-dup-c"],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(count, 2, "both attendees must persist");
        tx.commit().expect("commit");
    }
}
