use super::*;

mod gc_stale_sync_files_device_scope {
    use super::gc_stale_sync_files;
    use std::fs;
    use std::time::{Duration, SystemTime};

    /// Build an isolated sync directory for the test.
    fn temp_sync_dir(label: &str) -> std::path::PathBuf {
        let dir =
            std::env::temp_dir().join(format!("lorvex-fs-gc-{label}-{}", uuid::Uuid::now_v7()));
        fs::create_dir_all(&dir).expect("create sync dir");
        dir
    }

    fn test_conn() -> rusqlite::Connection {
        lorvex_store::open_db_in_memory().expect("open test db")
    }

    /// Backdate a file's mtime so the sweeper sees it as ancient.
    fn backdate(path: &std::path::Path, age_secs: u64) {
        let modified = SystemTime::now() - Duration::from_secs(age_secs);
        let f = fs::OpenOptions::new()
            .write(true)
            .open(path)
            .expect("open backdate target");
        f.set_modified(modified).expect("backdate mtime");
    }

    #[test]
    fn foreign_device_tmp_files_are_never_swept_regardless_of_age() {
        // a `.json.tmp` from another device may be in
        // the middle of the writer's atomic rename. Even if its mtime
        // looks ancient (e.g. clock skew on the shared folder, slow
        // filesystem timestamp resolution, NTP correction on the
        // peer), removing it would race the peer's `fs::rename` and
        // produce a phantom envelope drop. The sweeper must leave
        // foreign tmps in place.
        let sync_dir = temp_sync_dir("foreign-tmp");
        let conn = test_conn();
        let local_device_id = "device-local";

        let foreign_tmp = sync_dir.join(format!(
            "{}.json.tmp",
            super::filesystem_bridge_file_stem("device-peer", 42),
        ));
        fs::write(&foreign_tmp, b"{}").expect("seed foreign tmp");
        // 30-day-old tmp — more than any plausible threshold.
        backdate(&foreign_tmp, 30 * 86_400);

        gc_stale_sync_files(&conn, &sync_dir, local_device_id);

        assert!(
            foreign_tmp.exists(),
            "gc_stale_sync_files must NOT delete a foreign-device .json.tmp \
             — only the writing device knows whether its atomic rename has \
             landed yet (Issue #2986-M9)"
        );
    }

    #[test]
    fn local_device_tmp_files_are_swept_after_local_threshold() {
        // The fix must not regress local-tmp cleanup: an orphaned
        // local tmp from a crashed previous process is exactly the
        // case the sweeper exists to handle.
        let sync_dir = temp_sync_dir("local-tmp");
        let conn = test_conn();
        let local_device_id = "device-local";

        let local_tmp = sync_dir.join(format!(
            "{}.json.tmp",
            super::filesystem_bridge_file_stem(local_device_id, 99),
        ));
        fs::write(&local_tmp, b"{}").expect("seed local tmp");
        // 10-day-old tmp — past the 7-day local threshold.
        backdate(&local_tmp, 10 * 86_400);

        gc_stale_sync_files(&conn, &sync_dir, local_device_id);

        assert!(
            !local_tmp.exists(),
            "gc_stale_sync_files must reap orphaned local .json.tmp files \
             past the local threshold; otherwise crash artifacts accumulate"
        );
    }

    #[test]
    fn fresh_local_tmp_files_are_left_alone() {
        // A young local tmp belongs to a sibling thread mid-write;
        // even local tmps must respect the age threshold so the
        // sweeper can't race its own writer.
        let sync_dir = temp_sync_dir("fresh-local-tmp");
        let conn = test_conn();
        let local_device_id = "device-local";

        let local_tmp = sync_dir.join(format!(
            "{}.json.tmp",
            super::filesystem_bridge_file_stem(local_device_id, 99),
        ));
        fs::write(&local_tmp, b"{}").expect("seed fresh local tmp");
        // No backdate — file is brand new.

        gc_stale_sync_files(&conn, &sync_dir, local_device_id);

        assert!(
            local_tmp.exists(),
            "gc_stale_sync_files must not delete a freshly-written local tmp"
        );
    }

    #[test]
    fn foreign_json_envelopes_still_swept_after_full_resync_horizon() {
        // The device-scoping fix targets `.json.tmp` files only;
        // foreign `.json` envelopes must still be reaped after the
        // FULL_RESYNC_HORIZON cutoff or the shared folder grows
        // without bound.
        let sync_dir = temp_sync_dir("foreign-json");
        let conn = test_conn();
        let local_device_id = "device-local";

        let foreign_json = sync_dir.join(format!(
            "{}.json",
            super::filesystem_bridge_file_stem("device-peer", 7),
        ));
        fs::write(&foreign_json, b"{}").expect("seed foreign json envelope");
        let horizon_secs =
            u64::from(lorvex_domain::naming::FULL_RESYNC_HORIZON_DAYS) * 86_400 + 86_400;
        backdate(&foreign_json, horizon_secs);

        gc_stale_sync_files(&conn, &sync_dir, local_device_id);

        assert!(
            !foreign_json.exists(),
            "foreign .json envelopes past the FULL_RESYNC_HORIZON must still \
             be reaped — only foreign .tmp files are protected"
        );
    }

    #[test]
    fn unknown_extensions_are_ignored() {
        // A non-sync file that happens to live in the directory
        // (e.g. a `.DS_Store` from macOS Finder) must not be swept.
        let sync_dir = temp_sync_dir("ignore-ext");
        let conn = test_conn();
        let local_device_id = "device-local";

        let stray = sync_dir.join("README.txt");
        fs::write(&stray, b"hello").expect("seed stray file");
        backdate(&stray, 365 * 86_400);

        gc_stale_sync_files(&conn, &sync_dir, local_device_id);

        assert!(
            stray.exists(),
            "gc_stale_sync_files must only touch .json and .json.tmp files"
        );
    }

    #[test]
    fn read_dir_failure_is_persisted_to_error_logs() {
        let conn = test_conn();
        let missing_sync_dir =
            std::env::temp_dir().join(format!("lorvex-fs-gc-missing-{}", uuid::Uuid::now_v7()));

        gc_stale_sync_files(&conn, &missing_sync_dir, "device-local");

        let row: (String, String, String, String) = conn
            .query_row(
                "SELECT source, level, message, details
                 FROM error_logs
                 WHERE source = 'sync.filesystem_bridge.finalize.stale_file_gc'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read stale file GC diagnostic");

        assert_eq!(row.0, "sync.filesystem_bridge.finalize.stale_file_gc");
        assert_eq!(row.1, "warn");
        assert_eq!(
            row.2,
            "Filesystem bridge stale file GC could not read sync directory"
        );
        assert!(row
            .3
            .contains(&missing_sync_dir.to_string_lossy().to_string()));
    }
}
