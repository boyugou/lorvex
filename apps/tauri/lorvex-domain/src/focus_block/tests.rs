use super::*;

#[test]
fn parse_round_trips_every_variant() {
    for variant in [
        FocusBlockType::Task,
        FocusBlockType::Buffer,
        FocusBlockType::Event,
    ] {
        assert_eq!(FocusBlockType::parse(variant.as_str()), Some(variant));
    }
}

#[test]
fn parse_rejects_unknown_block_type() {
    // Pre-fix this would have silently rendered as a no-op
    // block — the typed parser surfaces the surprise so callers
    // can route it through validation.
    assert_eq!(FocusBlockType::parse("holiday"), None);
    assert_eq!(FocusBlockType::parse("Task"), None, "case-sensitive");
    assert_eq!(FocusBlockType::parse(""), None);
}

#[test]
fn requires_task_id_only_for_task_variant() {
    assert!(FocusBlockType::Task.requires_task_id());
    assert!(!FocusBlockType::Buffer.requires_task_id());
    assert!(!FocusBlockType::Event.requires_task_id());
}
