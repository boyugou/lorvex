#[cfg(desktop)]
use super::{clamp_to_visible_monitor, rect_overlaps_any_monitor, MonitorRect};
use super::{saturating_u32_to_i32, saturating_usize_to_i32};

#[test]
fn saturating_u32_to_i32_returns_max_on_overflow() {
    assert_eq!(saturating_u32_to_i32(u32::MAX), i32::MAX);
}

#[test]
fn saturating_usize_to_i32_returns_max_on_overflow() {
    assert_eq!(saturating_usize_to_i32(usize::MAX), i32::MAX);
}

#[cfg(desktop)]
#[test]
fn clamp_to_visible_monitor_keeps_position_inside_monitor() {
    let primary = MonitorRect {
        x: 0,
        y: 0,
        width: 1920,
        height: 1080,
    };
    // (200, 200) is well inside the available rect after the 12px
    // margin and 800x600 window size — the clamp should be a no-op.
    let pos = clamp_to_visible_monitor(200, 200, 800, 600, &[primary], Some(primary));
    assert_eq!(pos.x, 200);
    assert_eq!(pos.y, 200);
}

#[cfg(desktop)]
#[test]
fn clamp_to_visible_monitor_falls_back_when_off_screen() {
    let primary = MonitorRect {
        x: 0,
        y: 0,
        width: 1920,
        height: 1080,
    };
    // Off-screen request (-5000, -5000) — no monitor contains it,
    // so the helper falls back to clamping against `primary`.
    let pos = clamp_to_visible_monitor(-5000, -5000, 800, 600, &[primary], Some(primary));
    assert!(pos.x >= 0 && pos.x + 800 <= 1920);
    assert!(pos.y >= 0 && pos.y + 600 <= 1080);
}

#[cfg(desktop)]
#[test]
fn clamp_to_visible_monitor_picks_secondary_monitor_when_point_lives_there() {
    let primary = MonitorRect {
        x: 0,
        y: 0,
        width: 1920,
        height: 1080,
    };
    let secondary = MonitorRect {
        x: 1920,
        y: 0,
        width: 1920,
        height: 1080,
    };
    let pos = clamp_to_visible_monitor(2500, 200, 800, 600, &[primary, secondary], Some(primary));
    // Should stay on the secondary monitor — NOT get pulled back
    // to (0, 0) by a `.max(0)` clamp.
    assert_eq!(pos.x, 2500);
    assert_eq!(pos.y, 200);
}

#[cfg(desktop)]
#[test]
fn rect_overlaps_any_monitor_detects_off_screen_geometry() {
    let primary = MonitorRect {
        x: 0,
        y: 0,
        width: 1920,
        height: 1080,
    };
    assert!(rect_overlaps_any_monitor(100, 100, 800, 600, &[primary]));
    assert!(!rect_overlaps_any_monitor(
        -5000,
        -5000,
        800,
        600,
        &[primary]
    ));
}
