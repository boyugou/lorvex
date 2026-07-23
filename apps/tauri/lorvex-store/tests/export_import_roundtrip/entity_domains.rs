use super::support::*;

#[test]
fn test_habit_completions_roundtrip() {
    let dirs = setup_dirs();

    let source = open_db_in_memory().unwrap();
    source
        .execute(
            "INSERT INTO habits (id, name, frequency_type, target_count, archived,
                     created_at, updated_at, version)
             VALUES ('habit-1', 'Meditate', 'daily', 1, 0,
                     '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0060_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO habit_completions (habit_id, completed_date, value, note,
                     created_at, updated_at, version)
             VALUES ('habit-1', '2026-03-24', 1, 'Morning session',
                     '2026-03-24T08:00:00Z', '2026-03-24T08:00:00Z', '1711234567890_0061_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();

    export_to_zip(&source, &dirs.zip_path, "dev-1").unwrap();

    let target = open_db_in_memory().unwrap();
    import_from_zip(&target, &dirs.zip_path).unwrap();

    let completion_count: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM habit_completions WHERE habit_id = 'habit-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(completion_count, 1);

    let note: Option<String> = target
        .query_row(
            "SELECT note FROM habit_completions WHERE habit_id = 'habit-1' AND completed_date = '2026-03-24'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(note, Some("Morning session".to_string()));
}

// ---------------------------------------------------------------------------
// Child entities survive round-trip
// ---------------------------------------------------------------------------

#[test]
fn test_children_entities_roundtrip() {
    let dirs = setup_dirs();

    let source = open_db_in_memory().unwrap();
    source
        .execute(
            "INSERT INTO lists (id, name, version, created_at, updated_at)
             VALUES ('list-reminder', 'Reminders', '1711234567890_0069_11571157deadbeef', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
            [],
        )
        .unwrap();

    // Need a task for the reminder FK.
    source
        .execute(
            "INSERT INTO tasks (id, title, status, list_id, created_at, updated_at, version)
             VALUES ('task-1', 'Reminder target', 'open',
                     'list-reminder',
                     '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0070_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();

    // Task reminder.
    source
        .execute(
            "INSERT INTO task_reminders (id, task_id, reminder_at, created_at, version)
             VALUES ('rem-1', 'task-1', '2026-03-25T09:00:00Z',
                     '2026-03-24T00:00:00Z', '1711234567890_0071_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();

    export_to_zip(&source, &dirs.zip_path, "dev-1").unwrap();

    let target = open_db_in_memory().unwrap();
    import_from_zip(&target, &dirs.zip_path).unwrap();

    // Verify task reminder.
    let reminder_at: String = target
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE id = 'rem-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(reminder_at, "2026-03-25T09:00:00.000Z");
}

// ---------------------------------------------------------------------------
// Calendar events survive round-trip
// ---------------------------------------------------------------------------

#[test]
fn test_calendar_events_roundtrip() {
    let dirs = setup_dirs();

    let source = open_db_in_memory().unwrap();
    source
        .execute(
            "INSERT INTO calendar_events (id, title, description, start_date, start_time, end_date, end_time,
                     all_day, event_type, created_at, updated_at, version)
             VALUES ('evt-1', 'Team standup', 'Daily sync', '2026-03-25', '09:00', '2026-03-25', '09:30',
                     0, 'event',
                     '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0080_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();
    // Add attendees to verify embedded payload round-trip.
    source
        .execute(
            "INSERT INTO calendar_event_attendees (event_id, attendee_id, email, name, status)
             VALUES ('evt-1', 'email:alice@example.com', 'alice@example.com', 'Alice', 'accepted')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO calendar_event_attendees (event_id, attendee_id, email, name, status)
             VALUES ('evt-1', 'email:bob@example.com', 'bob@example.com', 'Bob', 'tentative')",
            [],
        )
        .unwrap();

    export_to_zip(&source, &dirs.zip_path, "dev-1").unwrap();

    let target = open_db_in_memory().unwrap();
    import_from_zip(&target, &dirs.zip_path).unwrap();

    let title: String = target
        .query_row(
            "SELECT title FROM calendar_events WHERE id = 'evt-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(title, "Team standup");

    let event_type: String = target
        .query_row(
            "SELECT event_type FROM calendar_events WHERE id = 'evt-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(event_type, "event");

    // Embedded child: attendees round-tripped.
    let attendee_count: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM calendar_event_attendees WHERE event_id = 'evt-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(attendee_count, 2, "attendees should round-trip");

    let alice_status: String = target
        .query_row(
            "SELECT status FROM calendar_event_attendees WHERE event_id = 'evt-1' AND email = 'alice@example.com'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(alice_status, "accepted");
}
