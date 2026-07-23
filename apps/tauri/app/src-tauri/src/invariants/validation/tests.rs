use super::*;

#[test]
fn title_rejects_empty() {
    assert!(validate_task_title("").is_err());
    assert!(validate_task_title("   ").is_err());
}

#[test]
fn title_accepts_normal() {
    assert!(validate_task_title("Buy groceries").is_ok());
}

#[test]
fn title_rejects_over_limit() {
    let long = "a".repeat(1_001);
    assert!(validate_task_title(&long).is_err());
}

#[test]
fn title_accepts_at_limit() {
    let exact = "a".repeat(1_000);
    assert!(validate_task_title(&exact).is_ok());
}

#[test]
fn body_accepts_none() {
    assert!(validate_task_body(None).is_ok());
}

#[test]
fn body_rejects_over_limit() {
    let long = "b".repeat(50_001);
    assert!(validate_task_body(Some(&long)).is_err());
}

#[test]
fn priority_accepts_valid_range() {
    for p in 1..=3 {
        assert!(validate_task_priority(Some(p)).is_ok());
    }
    assert!(validate_task_priority(None).is_ok());
}

#[test]
fn priority_rejects_out_of_range() {
    assert!(validate_task_priority(Some(0)).is_err());
    assert!(validate_task_priority(Some(4)).is_err());
    assert!(validate_task_priority(Some(-1)).is_err());
}

#[test]
fn tags_accepts_none() {
    assert!(validate_task_tags(None).is_ok());
}

#[test]
fn tags_rejects_too_many() {
    let tags: Vec<String> = (0..31).map(|i| format!("tag-{i}")).collect();
    assert!(validate_task_tags(Some(&tags)).is_err());
}

#[test]
fn tags_rejects_long_tag() {
    let long_tag = "x".repeat(2_001);
    let tags = vec![long_tag];
    assert!(validate_task_tags(Some(&tags)).is_err());
}
