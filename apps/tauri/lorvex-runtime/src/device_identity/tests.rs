use super::*;

fn setup_conn() -> Connection {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    conn.execute(
        "CREATE TABLE sync_checkpoints (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT",
        [],
    )
    .expect("create sync_checkpoints");
    conn
}

#[test]
fn get_or_create_device_id_persists_first_value() {
    let conn = setup_conn();

    let first = get_or_create_device_id(&conn).expect("create device id");
    let second = get_or_create_device_id(&conn).expect("reuse device id");

    assert_eq!(first, second);
    assert!(!first.trim().is_empty());
}

#[test]
fn hlc_suffix_is_correct_length_lowercase_hex() {
    let suffix = device_id_to_hlc_suffix("aabbccdd-1122-3344-5566-778899001122", HlcSurface::App);
    // widened from 8 to 16 hex chars (64 bits) so
    // cross-device birthday collisions stay vanishingly rare at
    // realistic install scales.
    assert_eq!(suffix.len(), HLC_DEVICE_SUFFIX_HEX_LEN);
    assert_eq!(suffix.len(), 16);
    assert!(suffix.chars().all(|c| c.is_ascii_hexdigit()));
    assert_eq!(suffix, suffix.to_ascii_lowercase());
}

#[test]
fn hlc_suffix_is_deterministic() {
    let a = device_id_to_hlc_suffix("aabbccdd-1122-3344-5566-778899001122", HlcSurface::Mcp);
    let b = device_id_to_hlc_suffix("aabbccdd-1122-3344-5566-778899001122", HlcSurface::Mcp);
    assert_eq!(a, b);
}

#[test]
fn hlc_suffix_differs_across_surfaces_for_same_device() {
    // the whole point of the surface tag. Same
    // device_id, three surfaces must yield three distinct suffixes
    // so same-ms writes from different processes don't collide.
    let device_id = "aabbccdd-1122-3344-5566-778899001122";
    let app = device_id_to_hlc_suffix(device_id, HlcSurface::App);
    let mcp = device_id_to_hlc_suffix(device_id, HlcSurface::Mcp);
    let cli = device_id_to_hlc_suffix(device_id, HlcSurface::Cli);
    assert_ne!(app, mcp);
    assert_ne!(mcp, cli);
    assert_ne!(app, cli);
}

#[test]
fn hlc_suffix_differs_across_devices_for_same_surface() {
    // Two UUIDv7s generated at the same millisecond share timestamp bits
    // but differ in random bits. Suffixes should be different.
    let uuid1 = "01936e3a-f000-7aaa-bbbb-111111111111";
    let uuid2 = "01936e3a-f000-7ccc-dddd-222222222222";
    assert_ne!(
        device_id_to_hlc_suffix(uuid1, HlcSurface::App),
        device_id_to_hlc_suffix(uuid2, HlcSurface::App),
    );
}

#[test]
fn hlc_suffix_case_insensitive_on_device_id() {
    // uppercase / mixed-case device_id hashes identically
    // to the canonical lowercase form.
    let lower = device_id_to_hlc_suffix("aabbccdd-1122-3344-5566-778899001122", HlcSurface::App);
    let upper = device_id_to_hlc_suffix("AABBCCDD-1122-3344-5566-778899001122", HlcSurface::App);
    assert_eq!(lower, upper);
}
