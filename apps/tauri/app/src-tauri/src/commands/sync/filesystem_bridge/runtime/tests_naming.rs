#[test]
fn file_stem_does_not_leak_device_id_or_outbox_id() {
    let device = "device-abcdef-1234-5678";
    let outbox_id: i64 = 987_654_321;
    let stem = super::filesystem_bridge_file_stem(device, outbox_id);
    assert!(
        !stem.contains(device),
        "file stem leaked raw device_id: {stem}"
    );
    assert!(
        !stem.contains("987654321"),
        "file stem leaked outbox sequence: {stem}"
    );
    // 16 hex + '_' + 16 hex = 33 chars.
    assert_eq!(stem.len(), 33, "stem length drift: {stem}");
    assert!(
        stem.chars().all(|c| c.is_ascii_hexdigit() || c == '_'),
        "stem must be hex-only with one separator: {stem}"
    );
}

#[test]
fn file_stem_is_deterministic_across_calls() {
    let stem_a = super::filesystem_bridge_file_stem("device-x", 42);
    let stem_b = super::filesystem_bridge_file_stem("device-x", 42);
    assert_eq!(stem_a, stem_b, "same inputs must produce same stem");
}

#[test]
fn file_stem_differs_for_distinct_envelopes_on_same_device() {
    let s1 = super::filesystem_bridge_file_stem("device-x", 1);
    let s2 = super::filesystem_bridge_file_stem("device-x", 2);
    assert_ne!(s1, s2);

    // The device-prefix portion (first 16 hex) MUST stay identical
    // so the local GC's prefix-match still works.
    assert_eq!(&s1[..16], &s2[..16]);
}

#[test]
fn file_stem_differs_for_same_outbox_id_on_distinct_devices() {
    let s1 = super::filesystem_bridge_file_stem("device-a", 7);
    let s2 = super::filesystem_bridge_file_stem("device-b", 7);
    assert_ne!(s1, s2);
    assert_ne!(&s1[..16], &s2[..16]);
}

#[test]
fn local_file_prefix_matches_device_part_of_stem() {
    let device = "device-local-prefix-test";
    let prefix = super::filesystem_bridge_local_file_prefix(device);
    let stem = super::filesystem_bridge_file_stem(device, 99);
    assert!(
        stem.starts_with(&prefix),
        "stem {stem} must start with local prefix {prefix}"
    );
}
