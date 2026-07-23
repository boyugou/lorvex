use super::status_filter_values;
use crate::contract::TaskStatusFilter;

#[test]
#[serial_test::serial(hlc)]
fn status_filter_values_omits_all_filter() {
    assert_eq!(status_filter_values(TaskStatusFilter::All).unwrap(), None);
}

#[test]
#[serial_test::serial(hlc)]
fn status_filter_values_serializes_non_all_filter() {
    assert_eq!(
        status_filter_values(TaskStatusFilter::Open).unwrap(),
        Some(vec!["open".to_string()])
    );
}
