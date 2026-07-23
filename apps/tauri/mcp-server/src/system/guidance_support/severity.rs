pub(crate) const fn severity_by_count(
    count: i64,
    high_threshold: i64,
    medium_threshold: i64,
) -> &'static str {
    if count >= high_threshold {
        "high"
    } else if count >= medium_threshold {
        "medium"
    } else {
        "low"
    }
}
