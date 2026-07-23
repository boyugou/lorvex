use super::utc_now_iso;

#[test]
#[serial_test::serial(hlc)]
fn utc_now_iso_uses_canonical_millisecond_sync_timestamp() {
    let mut previous = utc_now_iso();
    assert_eq!(previous.len(), 24, "unexpected timestamp width: {previous}");
    let previous_fraction = previous
        .split('.')
        .nth(1)
        .and_then(|tail| tail.strip_suffix('Z'))
        .expect("fraction");
    assert_eq!(previous_fraction.len(), 3);
    for _ in 0..256 {
        let next = utc_now_iso();
        let fraction = next
            .split('.')
            .nth(1)
            .and_then(|tail| tail.strip_suffix('Z'))
            .expect("fraction");
        assert_eq!(next.len(), 24, "unexpected timestamp width: {next}");
        assert_eq!(fraction.len(), 3);
        assert!(
            next >= previous,
            "timestamps must be lex non-decreasing: {previous} then {next}"
        );
        previous = next;
    }
}
