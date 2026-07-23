use super::support::*;

#[test]
fn test_empty_db_roundtrip() {
    let dirs = setup_dirs();

    let source = open_db_in_memory().unwrap();

    export_to_zip(&source, &dirs.zip_path, "dev-empty").unwrap();

    let target = open_db_in_memory().unwrap();
    let summary = import_from_zip(&target, &dirs.zip_path).unwrap();

    assert_eq!(
        serde_json::to_value(summary.scope_kind).unwrap(),
        serde_json::json!("full")
    );
    assert_eq!(summary.scope_categories, Vec::new());
    assert_eq!(
        serde_json::to_value(summary.dependency_mode).unwrap(),
        serde_json::json!("closure")
    );
    assert!(summary.validation_findings.is_empty());
}

// ---------------------------------------------------------------------------
// Older export replaces older target data (import updates stale data)
// ---------------------------------------------------------------------------

#[test]
fn test_import_updates_older_target_data() {
    let dirs = setup_dirs();

    // Source DB has a NEWER version.
    let source = open_db_in_memory().unwrap();
    source
        .execute(
            "INSERT INTO lists (id, name, color, created_at, updated_at, version)
             VALUES ('list-1', 'Updated Name', '#AAA', '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z',
                     '1811234567890_0000_cccccccccccccccc')",
            [],
        )
        .unwrap();

    export_to_zip(&source, &dirs.zip_path, "dev-1").unwrap();

    // Target DB has an OLDER version.
    let target = open_db_in_memory().unwrap();
    target
        .execute(
            "INSERT INTO lists (id, name, color, created_at, updated_at, version)
             VALUES ('list-1', 'Stale Name', '#000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
                     '1711234567890_0000_aaaaaaaaaaaaaaaa')",
            [],
        )
        .unwrap();

    let summary = import_from_zip(&target, &dirs.zip_path).unwrap();
    assert!(
        summary.entities_updated >= 1,
        "expected at least 1 entity updated"
    );

    // The newer import data should replace the stale target data.
    let list_name: String = target
        .query_row("SELECT name FROM lists WHERE id = 'list-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(list_name, "Updated Name");
}

// ---------------------------------------------------------------------------
// Offline export regression
// ---------------------------------------------------------------------------

/// First-launch offline path: a user who installs Lorvex on a plane (or any
/// environment without network) must be able to export their local data.
/// `export_to_zip` is, by construction, pure SQLite + filesystem I/O — it
/// takes a `&rusqlite::Connection` and writes to a `&Path`, with zero HTTP
/// or network dependencies in its call graph. This test pins that invariant
/// by exercising the full code path on a fresh in-memory DB and asserting
/// it completes successfully without touching any configured sync transport.
///
/// Note: we do not mock `reqwest` / `ureq` / the socket layer. The stronger
/// guarantee comes from the type signature (no Tauri `AppHandle`, no sync
/// transport, no `tokio` runtime passed in) — there is nowhere in this
/// crate's export path for a network call to live. If a future refactor
/// ever wires a network dependency into export, this test will still pass
/// byte-wise, but a companion module-level `forbid_network_deps` check
/// (tracked in `docs/execution/`) is the layer expected to catch such a
/// regression.
/// For now the test documents the invariant and gives us a quick smoke on
/// an empty DB so a "fresh-install offline" user cannot be broken by an
/// accidental SQL change that depends on seeded rows.
#[test]
fn test_export_works_offline_empty_db() {
    let dirs = setup_dirs();
    let source = open_db_in_memory().unwrap();

    // Fresh in-memory DB. No seeded data, no network fixture — if export
    // needed network, this call would hang or error on connect, not return
    // a clean manifest.
    let manifest = export_to_zip(&source, &dirs.zip_path, "offline-device").unwrap();

    assert_eq!(
        manifest.device_id, "offline-device",
        "device_id should be recorded in the manifest"
    );
    assert!(
        dirs.zip_path.exists(),
        "export zip should be written to disk even on a fresh install DB"
    );
    let zip_size = std::fs::metadata(&dirs.zip_path).unwrap().len();
    assert!(
        zip_size > 0,
        "exported zip should be non-empty (has manifest + seed rows)"
    );

    // A fresh in-memory DB may contain a small number of seed rows
    // (e.g. the default Inbox list). We don\u2019t assert exact emptiness —
    // the invariant we care about is that export *completes* without
    // needing network. Validate the archive round-trips into a second
    // in-memory DB.
    let target = open_db_in_memory().unwrap();
    import_from_zip(&target, &dirs.zip_path).unwrap();
}
