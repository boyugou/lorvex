use super::*;

#[test]
fn split_requires_exactly_one_separator_and_non_empty_halves() {
    assert_eq!(
        split_composite_edge_id("task:tag").unwrap(),
        ("task", "tag")
    );
    for invalid in ["", "task", "task:", ":tag", "task:tag:extra"] {
        assert!(
            split_composite_edge_id(invalid).is_err(),
            "{invalid:?} must be rejected"
        );
    }
}

#[test]
fn remap_rewrites_either_half_only_for_valid_ids() {
    assert_eq!(
        remap_composite_edge_id("task:tag", "task", "task-2").unwrap(),
        Some("task-2:tag".to_string())
    );
    assert_eq!(
        remap_composite_edge_id("task:tag", "tag", "tag-2").unwrap(),
        Some("task:tag-2".to_string())
    );
    assert_eq!(
        remap_composite_edge_id("task:tag", "missing", "x").unwrap(),
        None
    );
    assert!(remap_composite_edge_id("task:tag:extra", "tag", "x").is_err());
}
