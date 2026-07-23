use super::*;

#[test]
fn classify_cli_binary() {
    assert_eq!(classify_mcp_host("/usr/local/bin/lorvex"), McpHostKind::Cli);
    assert_eq!(
        classify_mcp_host("/opt/homebrew/bin/lorvex"),
        McpHostKind::Cli
    );
    assert_eq!(
        classify_mcp_host("/home/user/.cargo/bin/lorvex"),
        McpHostKind::Cli
    );
}

#[test]
fn classify_app_bundle_mcp() {
    assert_eq!(
        classify_mcp_host("/Applications/Lorvex.app/Contents/Resources/lorvex-mcp-server"),
        McpHostKind::App
    );
}

#[test]
fn classify_standalone_mcp_server_outside_app_bundle_is_unknown() {
    // Audit F9: a standalone `lorvex-mcp-server` outside an `.app`
    // bundle (e.g. `cargo install`'d, or a workspace dev build) is
    // not a recognized App install — the previous heuristic
    // misclassified these as `App` because of a dead branch in
    // `classify_mcp_host`. Pin the corrected behavior.
    assert!(matches!(
        classify_mcp_host("/usr/local/bin/lorvex-mcp-server"),
        McpHostKind::Unknown(_)
    ));
    assert!(matches!(
        classify_mcp_host("/Users/me/.cargo/bin/lorvex-mcp-server"),
        McpHostKind::Unknown(_)
    ));
}

#[test]
fn classify_standalone_mcp_server_inside_app_bundle_is_app() {
    assert_eq!(
        classify_mcp_host("/Applications/Lorvex.app/Contents/MacOS/lorvex-mcp-server"),
        McpHostKind::App
    );
}

/// pre-fix a hypothetical CLI helper bundled inside
/// an `.app` (e.g. `Lorvex.app/Contents/MacOS/lorvex`) hit the
/// trailing-`/lorvex` arm and was misclassified as `Cli`,
/// polluting MCP host authority decisions. The `.app/Contents/`
/// prefix gate ensures every binary inside an `.app` is owned
/// by the App surface regardless of basename.
#[test]
fn classify_cli_helper_inside_app_bundle_is_app() {
    assert_eq!(
        classify_mcp_host("/Applications/Lorvex.app/Contents/MacOS/lorvex"),
        McpHostKind::App
    );
    assert_eq!(
        classify_mcp_host("/Applications/Lorvex.app/Contents/Resources/lorvex"),
        McpHostKind::App
    );
    // Windows-style `.app\Contents\` separators (e.g. paths
    // round-tripped through a cross-platform serializer) match
    // the same gate.
    assert_eq!(
        classify_mcp_host("C:\\Apps\\Lorvex.app\\Contents\\MacOS\\lorvex"),
        McpHostKind::App
    );
}

/// the `Unknown` variant strips the directory
/// prefix so a persisted diagnostic export doesn't leak the
/// caller's sandbox / home-directory / network-share path.
/// Pre-fix the variant retained the raw input verbatim.
#[test]
fn unknown_variant_strips_directory_prefix() {
    match classify_mcp_host("/some/very-private/share/path/random-binary") {
        McpHostKind::Unknown(label) => {
            assert_eq!(label, "random-binary");
        }
        other => panic!("expected Unknown(_), got {other:?}"),
    }
    // Windows separator is honored too.
    match classify_mcp_host("C:\\Users\\alex\\Downloads\\random.exe") {
        McpHostKind::Unknown(label) => {
            assert_eq!(label, "random.exe");
        }
        other => panic!("expected Unknown(_), got {other:?}"),
    }
    // A path that's already a bare basename is preserved verbatim.
    match classify_mcp_host("random-binary") {
        McpHostKind::Unknown(label) => {
            assert_eq!(label, "random-binary");
        }
        other => panic!("expected Unknown(_), got {other:?}"),
    }
    // Trailing separator surfaces the placeholder rather than empty.
    match classify_mcp_host("/foo/") {
        McpHostKind::Unknown(label) => {
            assert_eq!(label, "<unknown>");
        }
        other => panic!("expected Unknown(_), got {other:?}"),
    }
}

#[test]
fn classify_unknown() {
    assert!(matches!(
        classify_mcp_host("/some/random/binary"),
        McpHostKind::Unknown(_)
    ));
}

#[cfg(target_os = "windows")]
#[test]
fn classify_windows_cli() {
    assert_eq!(
        classify_mcp_host("C:\\Users\\me\\AppData\\Local\\Lorvex\\lorvex.exe"),
        McpHostKind::Cli
    );
}

#[test]
fn persist_and_read_mcp_host_authority() {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    crate::local_state::initialize_local_runtime_tables(&conn).expect("init");

    assert!(get_mcp_host_authority(&conn).expect("read").is_none());

    let outcome = claim_mcp_host_authority(&conn, McpHostAuthorityKind::Cli).expect("set cli");
    assert_eq!(
        outcome,
        McpHostWriteOutcome::Stored,
        "first write must succeed (no prior row)"
    );
    assert_eq!(
        get_mcp_host_authority(&conn).expect("read").as_deref(),
        Some("cli")
    );

    // app has lower priority than cli, so a
    // straight `app` write at any timestamp loses the CAS — the
    // priority comparison runs first, before `updated_at`. To make
    // app authoritative we must first delete or downgrade the cli
    // row; this tests the priority-first ordering directly.
    std::thread::sleep(std::time::Duration::from_millis(2));
    let outcome = claim_mcp_host_authority(&conn, McpHostAuthorityKind::App).expect("set app");
    assert_eq!(
        outcome,
        McpHostWriteOutcome::LostRace,
        "lower-priority write must lose to a higher-priority stored row"
    );
    assert_eq!(
        get_mcp_host_authority(&conn).expect("read").as_deref(),
        Some("cli")
    );
}

/// writing the same host that's already stored
/// must report `AlreadyCorrect`, not `LostRace`. Pre-fix the API
/// returned `false` for both cases — a caller that retried on
/// `false` would loop forever, and a caller that escalated would
/// fire a false-positive "lost race" alarm.
#[test]
fn writing_same_host_reports_already_correct_not_lost_race() {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    crate::local_state::initialize_local_runtime_tables(&conn).expect("init");

    // Seed the row.
    let outcome = claim_mcp_host_authority(&conn, McpHostAuthorityKind::Cli).expect("seed cli");
    assert_eq!(outcome, McpHostWriteOutcome::Stored);

    // Sleep past the millisecond boundary so the CAS predicate
    // would otherwise admit the write at equal priority. The
    // outcome must still be AlreadyCorrect because the stored
    // host already matches the desired host.
    std::thread::sleep(std::time::Duration::from_millis(2));

    // Re-write the same host. The stored row will refresh because
    // updated_at is fresher (priority is equal), so the CAS
    // succeeds and the outcome is `Stored` — equivalent semantics:
    // the system IS in the desired state.
    //
    // To exercise the AlreadyCorrect branch we instead seed a row
    // with a strictly-fresher updated_at (so the CAS rejects) and
    // attempt to re-write the same host.
    conn.execute(
        "UPDATE mcp_host_authority SET updated_at = ?1 WHERE id = 1",
        rusqlite::params![i64::MAX / 2],
    )
    .unwrap();

    let outcome = claim_mcp_host_authority(&conn, McpHostAuthorityKind::Cli)
        .expect("re-write same host with stale ts");
    assert_eq!(
        outcome,
        McpHostWriteOutcome::AlreadyCorrect,
        "stored row already matches desired host: must report AlreadyCorrect"
    );
    assert_eq!(
        get_mcp_host_authority(&conn).expect("read").as_deref(),
        Some("cli")
    );
}

/// priority numbers are codified, not
/// derived from lex compare. `cli` outranks `app`; `Unknown`
/// (future kinds) starts at 0 so a typo never accidentally
/// outranks a known kind.
#[test]
fn mcp_host_priority_codifies_tier_order() {
    assert_eq!(mcp_host_priority(&McpHostKind::Cli), 2);
    assert_eq!(mcp_host_priority(&McpHostKind::App), 1);
    assert_eq!(mcp_host_priority(&McpHostKind::Unknown("future".into())), 0);
}

/// a lower-priority caller cannot win the CAS
/// even when its `updated_at` is strictly fresher. The priority
/// dimension dominates the tiebreak; updated_at only breaks ties
/// at equal priority.
#[test]
fn lower_priority_loses_even_with_fresher_timestamp() {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    crate::local_state::initialize_local_runtime_tables(&conn).expect("init");

    // Seed the high-priority `cli` row at an old timestamp.
    conn.execute(
        "INSERT INTO mcp_host_authority (id, host, priority, updated_at) \
         VALUES (1, 'cli', 2, ?1)",
        rusqlite::params![1_000_i64],
    )
    .unwrap();

    // Now `app` (priority 1) attempts to overwrite, with a much
    // fresher updated_at via the wall clock (~1.7e12).
    let outcome = claim_mcp_host_authority(&conn, McpHostAuthorityKind::App).expect("set app");
    assert_eq!(
        outcome,
        McpHostWriteOutcome::LostRace,
        "lower-priority write must lose even at fresher timestamp"
    );
    assert_eq!(
        get_mcp_host_authority(&conn).expect("read").as_deref(),
        Some("cli")
    );
}

#[test]
fn canonical_authority_kinds_round_trip() {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    crate::local_state::initialize_local_runtime_tables(&conn).expect("init");

    for (kind, expected) in [
        (McpHostAuthorityKind::App, "app"),
        (McpHostAuthorityKind::Cli, "cli"),
    ] {
        std::thread::sleep(std::time::Duration::from_millis(2));
        let outcome = claim_mcp_host_authority(&conn, kind).expect("set canonical");
        assert_eq!(
            outcome,
            McpHostWriteOutcome::Stored,
            "canonical kind {expected} must be stored"
        );
        assert_eq!(
            get_mcp_host_authority(&conn).expect("read").as_deref(),
            Some(expected)
        );
    }
}

#[test]
fn app_reclaim_overwrites_stale_cli_only_when_cli_missing() {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    crate::local_state::initialize_local_runtime_tables(&conn).expect("init");

    let missing_cli_path = std::env::temp_dir().join("lorvex-missing-cli-for-reclaim-test");
    conn.execute(
        "INSERT INTO mcp_host_authority (id, host, priority, host_path, updated_at)
         VALUES (1, 'cli', 2, ?1, 1000)",
        rusqlite::params![missing_cli_path.to_string_lossy().as_ref()],
    )
    .expect("seed stale cli authority");

    let denied =
        reclaim_app_mcp_host_authority_when_cli_missing(&conn, true).expect("reclaim denied");
    assert_eq!(denied, None);
    assert_eq!(
        get_mcp_host_authority(&conn).expect("read").as_deref(),
        Some("cli")
    );

    let reclaimed =
        reclaim_app_mcp_host_authority_when_cli_missing(&conn, false).expect("reclaim app");
    assert_eq!(reclaimed, Some(McpHostWriteOutcome::Stored));
    assert_eq!(
        get_mcp_host_authority(&conn).expect("read").as_deref(),
        Some("app")
    );

    let already =
        reclaim_app_mcp_host_authority_when_cli_missing(&conn, false).expect("reclaim app");
    assert_eq!(already, Some(McpHostWriteOutcome::AlreadyCorrect));
}

#[test]
fn app_reclaim_preserves_cli_authority_when_recorded_cli_path_is_valid_or_unknown() {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    crate::local_state::initialize_local_runtime_tables(&conn).expect("init");

    let valid_cli_path = std::env::current_exe().expect("current test exe");
    conn.execute(
        "INSERT INTO mcp_host_authority (id, host, priority, host_path, updated_at)
         VALUES (1, 'cli', 2, ?1, 1000)",
        rusqlite::params![valid_cli_path.to_string_lossy().as_ref()],
    )
    .expect("seed valid cli authority");
    let preserved =
        reclaim_app_mcp_host_authority_when_cli_missing(&conn, false).expect("reclaim app");
    assert_eq!(preserved, None);
    assert_eq!(
        get_mcp_host_authority(&conn).expect("read").as_deref(),
        Some("cli")
    );

    conn.execute(
        "UPDATE mcp_host_authority SET host_path = NULL WHERE id = 1",
        [],
    )
    .expect("clear cli path");
    let preserved =
        reclaim_app_mcp_host_authority_when_cli_missing(&conn, false).expect("reclaim app");
    assert_eq!(preserved, None);
    assert_eq!(
        get_mcp_host_authority(&conn).expect("read").as_deref(),
        Some("cli")
    );
}

#[test]
fn app_reclaim_loses_when_cli_claim_changes_the_row_after_read() {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    crate::local_state::initialize_local_runtime_tables(&conn).expect("init");

    let missing_cli_path = std::env::temp_dir().join("lorvex-missing-cli-race-test");
    conn.execute(
        "INSERT INTO mcp_host_authority (id, host, priority, host_path, updated_at)
         VALUES (1, 'cli', 2, ?1, 1000)",
        rusqlite::params![missing_cli_path.to_string_lossy().as_ref()],
    )
    .expect("seed stale cli authority");
    let stale_record = read_mcp_host_authority_record(&conn)
        .expect("read stale record")
        .expect("stale record");

    std::thread::sleep(std::time::Duration::from_millis(2));
    claim_mcp_host_authority(&conn, McpHostAuthorityKind::Cli).expect("fresh cli claim");

    let outcome = reclaim_app_mcp_host_authority_from_cli_record(&conn, &stale_record)
        .expect("stale app reclaim");
    assert_eq!(outcome, McpHostWriteOutcome::LostRace);
    assert_eq!(
        get_mcp_host_authority(&conn).expect("read").as_deref(),
        Some("cli")
    );
}

#[test]
fn cli_claim_retakes_authority_after_app_reclaim() {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    crate::local_state::initialize_local_runtime_tables(&conn).expect("init");

    reclaim_app_mcp_host_authority_when_cli_missing(&conn, false).expect("seed app");
    std::thread::sleep(std::time::Duration::from_millis(2));
    let outcome = claim_mcp_host_authority(&conn, McpHostAuthorityKind::Cli).expect("set cli");

    assert_eq!(outcome, McpHostWriteOutcome::Stored);
    assert_eq!(
        get_mcp_host_authority(&conn).expect("read").as_deref(),
        Some("cli")
    );
}

/// `path_is_executable_binary` rejects directories,
/// 0-byte files, and (on Unix) files without an execute bit.
#[test]
fn path_executability_rejects_zero_byte_and_non_executable() {
    let temp = tempfile::tempdir().expect("tempdir");
    let dir_path = temp.path().join("a-directory");
    std::fs::create_dir(&dir_path).expect("mkdir");
    assert!(
        !path_is_executable_binary(&dir_path),
        "directories rejected"
    );

    let zero_path = temp.path().join("zero-byte");
    std::fs::write(&zero_path, b"").expect("write zero");
    assert!(
        !path_is_executable_binary(&zero_path),
        "zero-byte file rejected"
    );

    let nonexistent = temp.path().join("does-not-exist");
    assert!(
        !path_is_executable_binary(&nonexistent),
        "missing path rejected"
    );

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let exec_path = temp.path().join("exec");
        std::fs::write(&exec_path, b"#!/bin/sh\necho lorvex\n").expect("write exec");
        std::fs::set_permissions(&exec_path, std::fs::Permissions::from_mode(0o755))
            .expect("chmod exec");
        assert!(
            path_is_executable_binary(&exec_path),
            "non-empty +x file accepted"
        );

        std::fs::set_permissions(&exec_path, std::fs::Permissions::from_mode(0o644))
            .expect("chmod -x");
        assert!(
            !path_is_executable_binary(&exec_path),
            "non-executable file rejected"
        );
    }
}

/// `classify_mcp_host` must use ASCII-only folding so a
/// Turkish-locale path doesn't change byte sequence under
/// `to_lowercase()` and miss the suffix match. Pin behavior with a
/// path containing a capital `I`.
#[test]
fn classify_uses_ascii_only_lowercasing() {
    // Mixed-case + capital I — under `to_lowercase()` on a Turkish
    // locale the I→ı conversion changes byte length; under
    // `to_ascii_lowercase()` it stays single-byte. The path ends in
    // the canonical CLI suffix so the match must succeed.
    assert_eq!(
        classify_mcp_host("/Applications/Installs/lorvex"),
        McpHostKind::Cli
    );
    assert_eq!(
        classify_mcp_host("/I/Some/Folder/lorvex.exe"),
        McpHostKind::Cli
    );
}

/// A stale write (same-or-older `updated_at`) at the same priority
/// MUST NOT clobber a fresher row in `mcp_host_authority`. Drives the
/// CAS guard directly via SQL against the typed `priority` column so
/// the assertion isn't sensitive to wall-clock resolution. The test
/// seeds and re-writes the SAME host so `excluded.priority ==
/// stored.priority` and the predicate falls through to the
/// `updated_at` comparison — isolating the timestamp half of the
/// tiebreak from the priority half.
#[test]
fn stale_claim_mcp_host_authority_does_not_overwrite_fresher_row() {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    crate::local_state::initialize_local_runtime_tables(&conn).expect("init");

    // Seed a fresh `cli` row at an absurdly high timestamp.
    conn.execute(
        "INSERT INTO mcp_host_authority (id, host, priority, updated_at) \
         VALUES (1, 'cli', 2, ?1)",
        rusqlite::params![9_999_999_999_999_i64],
    )
    .unwrap();

    // Re-write the same host via the public API. Same priority,
    // strictly older wall-clock timestamp, so the CAS rejects.
    // The outcome is `AlreadyCorrect` because the stored host
    // already matches the desired host (RT-H3 contract).
    let outcome = claim_mcp_host_authority(&conn, McpHostAuthorityKind::Cli).expect("set cli");
    assert_eq!(
        outcome,
        McpHostWriteOutcome::AlreadyCorrect,
        "stale same-host re-write must report AlreadyCorrect"
    );
    assert_eq!(
        get_mcp_host_authority(&conn).expect("read").as_deref(),
        Some("cli"),
        "fresher seeded value must persist after a stale write"
    );

    // Verify the updated_at didn't slide backwards either.
    let stored_ts: i64 = conn
        .query_row(
            "SELECT updated_at FROM mcp_host_authority WHERE id = 1",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(stored_ts, 9_999_999_999_999_i64);
}

/// integer comparison is the contract — a TEXT lex
/// compare misorders once digit count shifts. Confirm same-priority
/// CAS accepts a fresher numeric timestamp even when its decimal
/// form is shorter than the stored row's.
#[test]
fn integer_cas_accepts_fresher_value_with_shorter_text_form() {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    crate::local_state::initialize_local_runtime_tables(&conn).expect("init");

    // Seed `cli` with a tiny numeric timestamp whose decimal form
    // ("999") lex-compares HIGHER than a fresh wall-clock value
    // ("1740000000000") despite being numerically smaller.
    conn.execute(
        "INSERT INTO mcp_host_authority (id, host, priority, updated_at) \
         VALUES (1, 'cli', 2, ?1)",
        rusqlite::params![999_i64],
    )
    .unwrap();

    // Re-write same host. Equal priority, but wall-clock now is
    // numerically much greater than 999, so the CAS admits the
    // refresh.
    let outcome = claim_mcp_host_authority(&conn, McpHostAuthorityKind::Cli).expect("set cli");
    assert_eq!(
        outcome,
        McpHostWriteOutcome::Stored,
        "fresher numeric timestamp must win even when the prior row's text form is lex-higher"
    );
    let stored_ts: i64 = conn
        .query_row(
            "SELECT updated_at FROM mcp_host_authority WHERE id = 1",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        stored_ts > 999,
        "stored timestamp must be the fresh wall-clock value, got {stored_ts}"
    );
}

/// same-millisecond peers at equal priority
/// converge to whichever wrote first; subsequent same-ms writes are
/// rejected by the strict `>` predicate on `updated_at`. Drive the
/// underlying SQL directly so the test isn't sensitive to wall-clock
/// resolution.
#[test]
fn same_ms_tie_at_equal_priority_admits_first_write_only() {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    crate::local_state::initialize_local_runtime_tables(&conn).expect("init");

    let pinned_ts: i64 = 1_700_000_000_000;

    // First write: row is absent, INSERT succeeds.
    let affected = conn
        .execute(
            "INSERT INTO mcp_host_authority (id, host, priority, updated_at) \
             VALUES (1, 'cli', 2, ?1) \
             ON CONFLICT(id) DO UPDATE SET \
                 host = excluded.host, \
                 priority = excluded.priority, \
                 updated_at = excluded.updated_at \
             WHERE excluded.priority > mcp_host_authority.priority \
                OR (excluded.priority = mcp_host_authority.priority \
                    AND excluded.updated_at > mcp_host_authority.updated_at)",
            rusqlite::params![pinned_ts],
        )
        .unwrap();
    assert_eq!(affected, 1, "first cli write succeeds");

    // Second same-ms cli write at the same priority: the CAS
    // rejects because `excluded.updated_at > stored.updated_at` is
    // false at equality.
    let affected = conn
        .execute(
            "INSERT INTO mcp_host_authority (id, host, priority, updated_at) \
             VALUES (1, 'cli', 2, ?1) \
             ON CONFLICT(id) DO UPDATE SET \
                 host = excluded.host, \
                 priority = excluded.priority, \
                 updated_at = excluded.updated_at \
             WHERE excluded.priority > mcp_host_authority.priority \
                OR (excluded.priority = mcp_host_authority.priority \
                    AND excluded.updated_at > mcp_host_authority.updated_at)",
            rusqlite::params![pinned_ts],
        )
        .unwrap();
    assert_eq!(
        affected, 0,
        "same-ms equal-priority write must lose to the prior row"
    );
    assert_eq!(
        get_mcp_host_authority(&conn).expect("read").as_deref(),
        Some("cli")
    );
}
