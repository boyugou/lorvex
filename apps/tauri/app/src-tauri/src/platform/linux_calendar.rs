//! Linux native calendar reading -- scans local .ics files from XDG paths.
//!
//! GNOME Calendar and Evolution store calendar data as .ics files in standard
//! XDG data directories. This module recursively scans those directories,
//! parses VEVENT entries using the shared ICS parser from
//! `calendar_subscription_sync`, and upserts them into `provider_calendar_events`
//! with `provider_kind = 'linux_ics'`.

pub mod reader {
    #[cfg(any(target_os = "linux", test))]
    use crate::error::AppError;
    use crate::error::AppResult;
    use serde::Serialize;
    #[cfg(any(target_os = "linux", test))]
    use std::path::PathBuf;

    #[derive(Debug, Serialize)]
    pub struct LinuxCalendarSyncResult {
        pub events_imported: i64,
        pub events_updated: i64,
        pub events_removed: i64,
        pub files_scanned: i64,
        pub available: bool,
        pub error: Option<String>,
    }

    /// Route transient/per-file failures to `error_logs` so they
    /// surface in Settings → Diagnostics. `eprintln!` would be
    /// invisible on Linux release builds with no attached terminal.
    /// Mirrors the contract used by
    /// `platform::spotlight::log_spotlight_error`. Open a fresh DB
    /// handle on the calling thread because the Linux sync runs
    /// fire-and-forget from IPC; fall through silently if the DB
    /// itself is unreachable rather than crash the sync.
    #[cfg(any(target_os = "linux", test))]
    fn log_linux_calendar_warning(context: &str, message: &str) {
        let detail = format!("{context}: {message}");
        if let Ok(conn) = crate::db::get_conn() {
            let _ = crate::commands::diagnostics::append_error_log_internal(
                &conn,
                "platform.linux_calendar",
                &detail,
                None,
                Some("warn".to_string()),
            );
        }
    }

    #[cfg(any(target_os = "linux", test))]
    fn load_ics_file_contents(ics_paths: &[PathBuf]) -> Vec<(PathBuf, String)> {
        let mut loaded = Vec::with_capacity(ics_paths.len());
        for path in ics_paths {
            match std::fs::read_to_string(path) {
                Ok(content) => loaded.push((path.clone(), content)),
                Err(error) => {
                    log_linux_calendar_warning(
                        "skipping unreadable ics file",
                        &format!("{}: {error}", path.display()),
                    );
                }
            }
        }
        loaded
    }

    #[cfg(target_os = "linux")]
    pub fn sync_linux_calendars() -> AppResult<LinuxCalendarSyncResult> {
        use crate::commands::sync_timestamp_now;
        use crate::db::get_conn;
        use lorvex_workflow::calendar_subscription::parse_ics_events;
        use std::collections::HashSet;

        // Scan standard XDG calendar directories
        let mut ics_paths: Vec<PathBuf> = Vec::new();

        if let Some(data_dir) = dirs::data_dir() {
            // GNOME Calendar / Evolution data directories
            let evolution_dir = data_dir.join("evolution").join("calendar").join("local");
            let gnome_dir = data_dir.join("gnome-calendar").join("local");

            // KDE / Akonadi file-based calendar storage
            let akonadi_dir = data_dir.join("akonadi").join("file_db_data");

            for dir in [&evolution_dir, &gnome_dir, &akonadi_dir] {
                if dir.exists() {
                    extend_with_scanned(&mut ics_paths, dir);
                }
            }
        }

        if let Some(home) = dirs::home_dir() {
            // Fallback: ~/.local/share/evolution/calendar (already covered by
            // data_dir on most systems, but some distros differ)
            let alt_dir = home
                .join(".local")
                .join("share")
                .join("evolution")
                .join("calendar");
            if alt_dir.exists() {
                extend_with_scanned(&mut ics_paths, &alt_dir);
            }

            // Thunderbird: profiles use a random prefix (e.g. abcd1234.default-release)
            // so we glob ~/.thunderbird/*/calendar-data/
            let thunderbird_root = home.join(".thunderbird");
            if thunderbird_root.is_dir() {
                if let Ok(entries) = std::fs::read_dir(&thunderbird_root) {
                    for entry in entries.flatten() {
                        let ft = match entry.file_type() {
                            Ok(ft) => ft,
                            Err(_) => continue,
                        };
                        // Skip symlinks to avoid cycles, same as scan_ics_files
                        if ft.is_symlink() {
                            continue;
                        }
                        if ft.is_dir() {
                            let calendar_data = entry.path().join("calendar-data");
                            if calendar_data.is_dir() {
                                extend_with_scanned(&mut ics_paths, &calendar_data);
                            }
                        }
                    }
                }
            }
        }

        // Deduplicate paths (in case data_dir and the home fallback overlap)
        ics_paths.sort();
        ics_paths.dedup();

        if ics_paths.is_empty() {
            return Ok(LinuxCalendarSyncResult {
                events_imported: 0,
                events_updated: 0,
                events_removed: 0,
                files_scanned: 0,
                available: true,
                error: Some("No calendar .ics files found in standard locations.".to_string()),
            });
        }

        // Parse all .ics files and upsert events
        let conn = get_conn()?;
        let now_ts = sync_timestamp_now();
        let mut imported = 0i64;
        let mut updated = 0i64;
        let mut synced_keys: HashSet<String> = HashSet::new();
        let loaded_files = load_ics_file_contents(&ics_paths);

        for (path, content) in loaded_files {
            // Per-file tolerance: a single malformed `.ics` (truncated
            // mid-rotation by Evolution, encoding mismatch, future
            // calendar-app schema drift) is logged and skipped so the
            // loop preserves every already-parsed event. Propagating
            // the parse error with `?` would discard the whole batch
            // and leave the user's calendar empty. Log-and-skip
            // matches the resilience contract in
            // `load_ics_file_contents`.
            let events = match parse_ics_events(&content) {
                Ok(events) => events,
                Err(parse_err) => {
                    log_linux_calendar_warning(
                        "skipping malformed ics file",
                        &format!("{}: {parse_err}", path.display()),
                    );
                    continue;
                }
            };
            for event in &events {
                // Use UID+RECURRENCE-ID composite for detached overrides (parity with .ics subscription path).
                let event_key = match &event.recurrence_id {
                    Some(rid) if !rid.is_empty() => format!("{}+{}", event.uid, rid),
                    _ => event.uid.clone(),
                };
                synced_keys.insert(event_key.clone());

                let recurrence_json = event
                    .rrule
                    .as_deref()
                    .and_then(lorvex_workflow::calendar_subscription::rrule_to_json);
                let outcome = lorvex_store::repositories::provider_repo::upsert_provider_event(
                    &conn,
                    &lorvex_store::repositories::provider_repo::ProviderEventData {
                        provider_kind: "linux_ics",
                        provider_scope: "",
                        provider_event_key: &event_key,
                        title: Some(event.summary.as_str()),
                        description: event.description.as_deref(),
                        start_date: &event.start_date,
                        start_time: event.start_time.as_deref(),
                        end_date: event.end_date.as_deref(),
                        end_time: event.end_time.as_deref(),
                        all_day: event.all_day,
                        location: event.location.as_deref(),
                        organizer_email: event.organizer.as_deref(),
                        source_time_kind: &event.source_time_kind,
                        source_tzid: event.source_tzid.as_deref(),
                        recurrence: recurrence_json.as_deref(),
                        recurrence_exceptions: event.exdates_json.as_deref(),
                        color: None,
                        attendees_json: event.attendees_json.as_deref(),
                        video_call_url: event.url.as_deref(),
                    },
                    &now_ts,
                )?;
                match outcome {
                    lorvex_store::repositories::provider_repo::ProviderEventUpsertOutcome::Inserted => {
                        imported += 1;
                    }
                    lorvex_store::repositories::provider_repo::ProviderEventUpsertOutcome::Updated => {
                        updated += 1;
                    }
                    lorvex_store::repositories::provider_repo::ProviderEventUpsertOutcome::Unchanged => {}
                }
            }
        }

        // Remove stale events that no longer exist in any .ics file
        let mut removed = 0i64;
        let cached_keys = lorvex_store::repositories::provider_repo::get_provider_event_keys(
            &conn,
            "linux_ics",
            None,
            None,
        )?;
        for key in &cached_keys {
            if !synced_keys.contains(key) {
                lorvex_store::repositories::provider_repo::delete_provider_event(
                    &conn,
                    "linux_ics",
                    "",
                    key,
                )?;
                removed += 1;
            }
        }

        // Record successful refresh so shared timeline/blocking queries include Linux events.
        crate::platform::provider_scope_state::record_refresh_success(
            &conn,
            "linux_ics",
            "",
            &now_ts,
        )?;

        Ok(LinuxCalendarSyncResult {
            events_imported: imported,
            events_updated: updated,
            events_removed: removed,
            files_scanned: ics_paths.len() as i64,
            available: true,
            error: None,
        })
    }

    /// log-and-skip a single calendar root that fails
    /// to scan, instead of `?`-propagating and discarding every other
    /// root that already succeeded. A transient permission flip on one
    /// directory (e.g. Akonadi rewriting `file_db_data` mid-scan) used
    /// to wipe the entire Linux calendar set; per-root tolerance keeps
    /// the rest of the user's calendars visible.
    #[cfg(target_os = "linux")]
    fn extend_with_scanned(ics_paths: &mut Vec<std::path::PathBuf>, dir: &std::path::Path) {
        match scan_ics_files(dir) {
            Ok(found) => ics_paths.extend(found),
            Err(error) => {
                log_linux_calendar_warning(
                    "skipping unreadable calendar root",
                    &format!("{}: {error}", dir.display()),
                );
            }
        }
    }

    /// Recursively scan a directory for .ics files.
    ///
    /// Guards against unbounded recursion:
    /// - `depth` is capped at `MAX_SCAN_DEPTH` (10 levels) and overflow fails fast.
    /// - Symlinks are skipped to prevent cycles.
    /// - File discovery is capped at `MAX_SCAN_FILES` (1 000) and overflow fails fast.
    #[cfg(any(target_os = "linux", test))]
    fn scan_ics_files(dir: &std::path::Path) -> AppResult<Vec<std::path::PathBuf>> {
        const MAX_SCAN_DEPTH: u32 = 10;
        const MAX_SCAN_FILES: usize = 1_000;

        fn scan_inner(
            dir: &std::path::Path,
            paths: &mut Vec<std::path::PathBuf>,
            depth: u32,
        ) -> AppResult<()> {
            if depth > MAX_SCAN_DEPTH {
                return Err(AppError::Internal(format!(
                    "Linux calendar scan depth limit exceeded at {} (max depth {MAX_SCAN_DEPTH})",
                    dir.display()
                )));
            }
            let entries = std::fs::read_dir(dir).map_err(|error| {
                AppError::Internal(format!(
                    "Failed to read Linux calendar directory {}: {error}",
                    dir.display()
                ))
            })?;
            for entry in entries {
                let entry = entry.map_err(|error| {
                    AppError::Internal(format!(
                        "Failed to read Linux calendar directory entry in {}: {error}",
                        dir.display()
                    ))
                })?;
                // Skip symlinks to avoid cycles.
                let ft = entry.file_type().map_err(|error| {
                    AppError::Internal(format!(
                        "Failed to inspect Linux calendar directory entry {}: {error}",
                        entry.path().display()
                    ))
                })?;
                if ft.is_symlink() {
                    continue;
                }
                let path = entry.path();
                if ft.is_file() && path.extension().is_some_and(|ext| ext == "ics") {
                    if paths.len() >= MAX_SCAN_FILES {
                        return Err(AppError::Internal(format!(
                            "Linux calendar file scan limit exceeded in {} (max files {MAX_SCAN_FILES})",
                            dir.display()
                        )));
                    }
                    paths.push(path);
                } else if ft.is_dir() {
                    scan_inner(&path, paths, depth + 1)?;
                }
            }

            Ok(())
        }

        let mut paths = Vec::new();
        scan_inner(dir, &mut paths, 0)?;
        Ok(paths)
    }

    /// Non-Linux stub: returns unavailable.
    #[cfg(not(target_os = "linux"))]
    pub fn sync_linux_calendars() -> AppResult<LinuxCalendarSyncResult> {
        Ok(LinuxCalendarSyncResult {
            events_imported: 0,
            events_updated: 0,
            events_removed: 0,
            files_scanned: 0,
            available: false,
            error: Some("Linux calendar reading is only available on Linux.".to_string()),
        })
    }

    #[cfg(test)]
    mod tests {
        use super::{load_ics_file_contents, scan_ics_files};
        #[cfg(unix)]
        use std::os::unix::fs::PermissionsExt;

        #[test]
        fn load_ics_file_contents_skips_unreadable_paths() {
            let dir = tempfile::tempdir().expect("temp dir");
            let missing = dir.path().join("missing.ics");
            let valid = dir.path().join("valid.ics");
            std::fs::write(&valid, "BEGIN:VCALENDAR\nEND:VCALENDAR\n").expect("write valid");

            let loaded = load_ics_file_contents(&[missing, valid.clone()]);
            assert_eq!(
                loaded.len(),
                1,
                "unreadable file should be skipped, valid file kept"
            );
            assert_eq!(loaded[0].0, valid);
        }

        #[test]
        fn load_ics_file_contents_reads_all_requested_files() {
            let dir = tempfile::tempdir().expect("temp dir");
            let first = dir.path().join("first.ics");
            let second = dir.path().join("second.ics");
            std::fs::write(&first, "BEGIN:VCALENDAR\nEND:VCALENDAR\n").expect("write first");
            std::fs::write(&second, "BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR\n")
                .expect("write second");

            let loaded = load_ics_file_contents(&[first.clone(), second.clone()]);

            assert_eq!(loaded.len(), 2);
            assert_eq!(loaded[0].0, first);
            assert!(loaded[0].1.contains("BEGIN:VCALENDAR"));
            assert_eq!(loaded[1].0, second);
            assert!(loaded[1].1.contains("VERSION:2.0"));
        }

        #[test]
        fn scan_ics_files_collects_nested_ics_files() {
            let dir = tempfile::tempdir().expect("temp dir");
            let nested = dir.path().join("nested");
            std::fs::create_dir(&nested).expect("create nested dir");
            let first = dir.path().join("root.ics");
            let second = nested.join("nested.ics");
            std::fs::write(&first, "BEGIN:VCALENDAR\nEND:VCALENDAR\n").expect("write root ics");
            std::fs::write(&second, "BEGIN:VCALENDAR\nEND:VCALENDAR\n").expect("write nested ics");

            let mut scanned = scan_ics_files(dir.path()).expect("scan readable calendar dirs");
            scanned.sort();
            let mut expected = vec![first, second];
            expected.sort();

            assert_eq!(scanned, expected);
        }

        #[cfg(unix)]
        #[test]
        fn scan_ics_files_rejects_unreadable_subdirectories() {
            let dir = tempfile::tempdir().expect("temp dir");
            let blocked = dir.path().join("blocked");
            std::fs::create_dir(&blocked).expect("create blocked dir");
            std::fs::set_permissions(&blocked, std::fs::Permissions::from_mode(0o000))
                .expect("make blocked dir unreadable");

            let error = scan_ics_files(dir.path())
                .expect_err("unreadable calendar subdirectory should fail fast");
            let message = error.to_string();
            assert!(
                message.contains("Failed to read Linux calendar directory"),
                "unexpected error: {message}"
            );

            std::fs::set_permissions(&blocked, std::fs::Permissions::from_mode(0o700))
                .expect("restore blocked dir permissions");
        }

        #[test]
        fn scan_ics_files_rejects_directory_trees_deeper_than_scan_limit() {
            let dir = tempfile::tempdir().expect("temp dir");
            let mut current = dir.path().to_path_buf();
            for depth in 0..=10 {
                current = current.join(format!("level-{depth}"));
                std::fs::create_dir(&current).expect("create nested dir");
            }
            let deep_ics = current.join("deep.ics");
            std::fs::write(&deep_ics, "BEGIN:VCALENDAR\nEND:VCALENDAR\n").expect("write deep ics");

            let error = scan_ics_files(dir.path())
                .expect_err("directory trees deeper than the scan limit should fail");
            let message = error.to_string();
            assert!(
                message.contains("scan depth limit"),
                "unexpected error: {message}"
            );
        }

        #[test]
        fn scan_ics_files_rejects_file_counts_above_scan_limit() {
            let dir = tempfile::tempdir().expect("temp dir");
            for index in 0..=1_000 {
                let path = dir.path().join(format!("event-{index:04}.ics"));
                std::fs::write(&path, "BEGIN:VCALENDAR\nEND:VCALENDAR\n")
                    .expect("write calendar file");
            }

            let error = scan_ics_files(dir.path())
                .expect_err("file counts above the scan limit should fail");
            let message = error.to_string();
            assert!(
                message.contains("file scan limit"),
                "unexpected error: {message}"
            );
        }
    }
}
