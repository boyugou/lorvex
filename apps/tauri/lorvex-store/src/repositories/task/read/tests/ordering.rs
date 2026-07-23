//! Canonical ordering invariants. Pins the exact `TASK_ORDER_BY`
//! string so any drift surfaces as a reviewable diff — every
//! production caller depends on this shape for stable OFFSET
//! pagination.

use super::support::TASK_ORDER_BY;

/// Canonical ORDER BY string must not drift — every production caller
/// depends on this exact shape.
#[test]
fn task_order_by_is_id_stable_canonical() {
    assert_eq!(
        TASK_ORDER_BY,
        "priority_effective ASC, due_date ASC NULLS LAST, id ASC"
    );
}
