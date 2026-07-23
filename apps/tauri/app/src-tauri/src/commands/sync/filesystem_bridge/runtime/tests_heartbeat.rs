use super::*;

mod lease_heartbeat_wiring {
    use super::super::super::lease_heartbeat::{tick, HeartbeatGuard};
    use super::phase_push_to_filesystem;
    use lorvex_sync::envelope::{SyncEnvelope, SyncOperation};
    use std::fs;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use std::time::Duration;

    use crate::test_support::test_conn;

    fn enqueue_simple(conn: &rusqlite::Connection, suffix: &str) -> i64 {
        // `Hlc::parse` enforces a strict
        // 16-char lowercase-hex device suffix. The pre-flip fixture
        // built an 8-char `dev{suffix}aaaa` payload that silently
        // failed parse-time validation. Hex-encode the per-row tag
        // and right-pad to the canonical 16-hex width so each enqueued
        // envelope still ends up with a unique, lex-ordered suffix
        // (the heartbeat wiring tests don't care about the payload —
        // they care about per-row tick accountancy).
        let hex_tag: String = suffix.bytes().map(|b| format!("{b:02x}")).collect();
        let suffix_hex = format!("{hex_tag:0<16}");
        let version_str = format!("0001743573600000_0000_{suffix_hex}");
        let envelope = SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::Task,
            entity_id: format!("01966a3f-7c8b-7d4e-8f3a-000000000f0{suffix}"),
            operation: SyncOperation::Upsert,
            version: lorvex_domain::hlc::Hlc::parse(&version_str).expect("test fixture HLC"),
            payload_schema_version: 1,
            payload:
                serde_json::json!({"id": format!("01966a3f-7c8b-7d4e-8f3a-000000000f0{suffix}"), "title": "T", "status": "open"})
                    .to_string(),
            device_id: "device-tick-test".to_string(),
        };
        lorvex_sync::outbox::enqueue(conn, &envelope).expect("enqueue");
        conn.query_row(
            "SELECT id FROM sync_outbox ORDER BY id DESC LIMIT 1",
            [],
            |row| row.get(0),
        )
        .expect("id")
    }

    #[test]
    fn push_loop_ticks_heartbeat_once_per_outbox_entry() {
        // Run on a dedicated thread so the heartbeat thread-local can
        // be exercised in isolation (and doesn't leak into other
        // tests sharing the worker pool).
        std::thread::spawn(|| {
            let conn = test_conn();
            for s in ["a", "b", "c", "d", "e"] {
                enqueue_simple(&conn, s);
            }

            let temp =
                std::env::temp_dir().join(format!("lorvex-fs-push-tick-{}", uuid::Uuid::now_v7()));
            let sync_dir = temp.join("sync");
            fs::create_dir_all(&sync_dir).expect("create sync dir");

            let pending = lorvex_sync::outbox::get_pending(&conn).expect("pending");
            assert_eq!(pending.len(), 5, "fixture must produce five pending rows");

            let counter = Arc::new(AtomicUsize::new(0));
            let counter_clone = counter.clone();
            // Zero-duration interval so every tick fires the renewer
            // — this isolates the wiring from any time-based race
            // (CI under load can suspend the test thread for >10 s,
            // which would otherwise have to be the heartbeat
            // interval to be exercised at all).
            let _guard = HeartbeatGuard::install(Duration::from_millis(0), move || {
                counter_clone.fetch_add(1, Ordering::SeqCst);
                Ok(())
            });

            let outcome =
                phase_push_to_filesystem(pending, &sync_dir).expect("push under heartbeat");
            assert_eq!(outcome.pushed_ids.len(), 5);

            assert_eq!(
                counter.load(Ordering::SeqCst),
                5,
                "phase_push_to_filesystem must tick the heartbeat exactly once \
                 per pending outbox entry (Issue #2986-M17)"
            );
        })
        .join()
        .unwrap();
    }

    #[test]
    fn push_loop_aborts_on_heartbeat_failure() {
        // if the heartbeat reports a lost lease the
        // push loop must surface the error rather than continue to
        // race the new owner.
        std::thread::spawn(|| {
            let conn = test_conn();
            for s in ["a", "b", "c"] {
                enqueue_simple(&conn, s);
            }
            let temp = std::env::temp_dir()
                .join(format!("lorvex-fs-push-tick-fail-{}", uuid::Uuid::now_v7()));
            let sync_dir = temp.join("sync");
            fs::create_dir_all(&sync_dir).expect("create sync dir");

            let pending = lorvex_sync::outbox::get_pending(&conn).expect("pending");
            let _guard = HeartbeatGuard::install(Duration::from_millis(0), || {
                Err(crate::error::AppError::Internal(
                    "lease lost mid-push".to_string(),
                ))
            });
            let result = phase_push_to_filesystem(pending, &sync_dir);
            let Err(err) = result else {
                panic!("push must abort when heartbeat reports lease lost, but it returned Ok",)
            };
            assert!(
                err.to_string().contains("lease lost mid-push"),
                "unexpected error message: {err}"
            );

            // No envelopes should have been written — the loop bails
            // before opening the first tmp.
            let written = fs::read_dir(&sync_dir)
                .map(std::iter::Iterator::count)
                .unwrap_or(0);
            assert_eq!(
                written, 0,
                "push must not publish any envelopes after lease loss"
            );
        })
        .join()
        .unwrap();
    }

    #[test]
    fn tick_is_noop_when_no_guard_is_installed() {
        // Sanity check for the production no-op path used by direct
        // unit-test invocations of phase_push_to_filesystem and
        // collect_remote_filesystem_bridge_envelopes.
        std::thread::spawn(|| {
            for _ in 0..1_000 {
                tick().expect("no-guard tick must always succeed");
            }
        })
        .join()
        .unwrap();
    }
}
