use super::*;

#[test]
fn format_is_correct() {
    let key = generate_instance_key("grp-abc", "2026-04-01").unwrap();
    assert_eq!(key, "grp-abc:2026-04-01");
}

#[test]
fn generate_returns_none_for_empty_group_id() {
    assert!(generate_instance_key("", "2026-03-25").is_none());
}

#[test]
fn deterministic_across_devices() {
    // Two devices computing the same recurrence should produce the same key.
    let group_id = "01966a3f-7c8b-7d4e-8f3a-000000000001";
    let canonical_date = "2026-03-25";
    let key_device_a = generate_instance_key(group_id, canonical_date).unwrap();
    let key_device_b = generate_instance_key(group_id, canonical_date).unwrap();
    assert_eq!(key_device_a, key_device_b);
}

#[test]
fn instance_key_format() {
    let key = generate_instance_key("group-1", "2026-04-05");
    assert_eq!(key, Some("group-1:2026-04-05".to_string()));
}

/// a malformed date side must be rejected.
/// Pre-fix the function only validated the group_id; "not-a-date"
/// would round-trip into the key and pollute downstream LIKE/
/// exact-match queries.
#[test]
fn rejects_non_canonical_date() {
    assert!(generate_instance_key("group-1", "not-a-date").is_none());
    assert!(generate_instance_key("group-1", "2026-4-5").is_none()); // missing zero pad
    assert!(generate_instance_key("group-1", "2026-04-05T00:00").is_none()); // RFC3339
    assert!(generate_instance_key("group-1", "").is_none());
    assert!(generate_instance_key("group-1", "2026/04/05").is_none()); // wrong separator
}

/// shape validation alone accepted semantically
/// bogus dates like `2026-13-99` (month 13, day 99). The check
/// must reject any string `chrono::NaiveDate` cannot parse.
#[test]
fn rejects_out_of_range_calendar_dates() {
    assert!(generate_instance_key("group", "2026-13-99").is_none());
    assert!(generate_instance_key("group", "2026-00-01").is_none()); // month 0
    assert!(generate_instance_key("group", "2026-02-30").is_none()); // Feb 30
    assert!(generate_instance_key("group", "2025-02-29").is_none()); // non-leap Feb 29
    assert!(generate_instance_key("group", "2026-12-32").is_none()); // day 32
                                                                     // Sanity: real leap day still passes.
    assert!(generate_instance_key("group", "2024-02-29").is_some());
}

/// expanded the rejected alphabet to cover SQL
/// LIKE wildcards (`%` / `_`) and ASCII control bytes alongside
/// the existing `:` / whitespace gate. Pre-fix a malformed peer
/// payload could smuggle a `%` into the group_id, producing a
/// key that masquerades as a wildcard prefix in downstream LIKE
/// queries.
#[test]
fn rejects_dangerous_characters_in_group_id() {
    assert!(generate_instance_key("grp:colon", "2026-04-05").is_none());
    assert!(generate_instance_key("grp space", "2026-04-05").is_none());
    assert!(generate_instance_key("grp%pct", "2026-04-05").is_none());
    assert!(generate_instance_key("grp_under", "2026-04-05").is_none());
    assert!(generate_instance_key("grp\nlf", "2026-04-05").is_none());
    assert!(generate_instance_key("grp\tab", "2026-04-05").is_none());
    assert!(generate_instance_key("grp\0nul", "2026-04-05").is_none());
    // Sanity: hyphenated UUIDs and bare hex labels still pass.
    assert!(generate_instance_key("01966a3f-7c8b-7d4e-8f3a-000000000001", "2026-04-05").is_some());
    assert!(generate_instance_key("grp-abc", "2026-04-05").is_some());
}
