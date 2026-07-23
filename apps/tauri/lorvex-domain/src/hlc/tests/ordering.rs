use crate::hlc::*;

#[test]
fn lexicographic_ordering_matches_component_ordering() {
    let a = Hlc::new(1000, 0, "aaaa0000aaaa0000").unwrap();
    let b = Hlc::new(2000, 0, "aaaa0000aaaa0000").unwrap();
    assert!(a < b, "earlier physical_ms should be less");

    // String sort should match.
    assert!(a.to_string() < b.to_string());
}

#[test]
fn ordering_by_counter_when_physical_ms_equal() {
    let a = Hlc::new(1000, 1, "aaaa0000aaaa0000").unwrap();
    let b = Hlc::new(1000, 2, "aaaa0000aaaa0000").unwrap();
    assert!(a < b, "lower counter should be less");
    assert!(a.to_string() < b.to_string());
}

#[test]
fn ordering_by_device_suffix_when_physical_ms_and_counter_equal() {
    let a = Hlc::new(1000, 0, "aaaa0000aaaa0000").unwrap();
    let b = Hlc::new(1000, 0, "bbbb0000bbbb0000").unwrap();
    assert!(a < b, "lexicographically earlier suffix should be less");
    assert!(a.to_string() < b.to_string());
}

#[test]
fn comparison_equal() {
    let a = Hlc::new(5000, 10, "deadbeefdeadbeef").unwrap();
    let b = Hlc::new(5000, 10, "deadbeefdeadbeef").unwrap();
    assert_eq!(a, b);
    assert_eq!(a.cmp(&b), std::cmp::Ordering::Equal);
}
