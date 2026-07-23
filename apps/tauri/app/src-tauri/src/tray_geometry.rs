use crate::desktop_geometry::saturating_u32_to_i32;

/// Logical dimensions of the popover window (matches `inner_size` in popover.rs).
pub(crate) const TRAY_POPOVER_LOGICAL_WIDTH: i32 = 380;
const TRAY_POPOVER_LOGICAL_HEIGHT: i32 = 420;
pub(crate) const TRAY_POPOVER_LOGICAL_X_MARGIN: i32 = 8;
pub(crate) const TRAY_POPOVER_LOGICAL_Y_MARGIN: i32 = 6;

const fn position_to_physical_coords(position: tauri::Position) -> (i32, i32) {
    match position {
        tauri::Position::Physical(position) => (position.x, position.y),
        tauri::Position::Logical(position) => {
            (position.x.round() as i32, position.y.round() as i32)
        }
    }
}

fn size_to_physical_dimensions(size: tauri::Size) -> (i32, i32) {
    match size {
        tauri::Size::Physical(size) => (
            saturating_u32_to_i32(size.width),
            saturating_u32_to_i32(size.height),
        ),
        tauri::Size::Logical(size) => (size.width.round() as i32, size.height.round() as i32),
    }
}

pub(crate) fn rect_to_physical_bounds(rect: tauri::Rect) -> (i32, i32, i32, i32) {
    let (x, y) = position_to_physical_coords(rect.position);
    let (width, height) = size_to_physical_dimensions(rect.size);
    (x, y, width, height)
}

/// Find which monitor contains the given physical-pixel point by iterating all
/// available monitors.  This avoids `monitor_from_point` which on macOS expects
/// logical (point) coordinates while Tauri's tray rect reports physical pixels,
/// causing wrong-monitor selection on Retina / multi-monitor setups.
pub(crate) fn find_monitor_containing_physical_point(
    app: &tauri::AppHandle,
    px: i32,
    py: i32,
) -> Option<tauri::Monitor> {
    app.available_monitors()
        .ok()
        .and_then(|monitors| {
            monitors.into_iter().find(|m| {
                let pos = m.position();
                let size = m.size();
                let mw = saturating_u32_to_i32(size.width);
                let mh = saturating_u32_to_i32(size.height);
                let max_x = pos.x.saturating_add(mw);
                let max_y = pos.y.saturating_add(mh);
                px >= pos.x && px < max_x && py >= pos.y && py < max_y
            })
        })
        .or_else(|| app.primary_monitor().ok().flatten())
}

/// Compute the popover position (physical pixels) clamped to the given monitor.
///
/// All tray coordinates and monitor bounds are in physical pixels.
/// `scale_factor` is used to convert the logical popover dimensions
/// (`TRAY_POPOVER_LOGICAL_*`) to physical so the clamping math is consistent.
pub(crate) fn clamp_tray_popover_position_to_monitor(
    tray_x: i32,
    tray_y: i32,
    tray_width: i32,
    tray_height: i32,
    monitor_pos: tauri::PhysicalPosition<i32>,
    monitor_size: tauri::PhysicalSize<u32>,
    scale_factor: f64,
) -> (i32, i32) {
    let popover_w = (f64::from(TRAY_POPOVER_LOGICAL_WIDTH) * scale_factor).round() as i32;
    let popover_h = (f64::from(TRAY_POPOVER_LOGICAL_HEIGHT) * scale_factor).round() as i32;
    let x_margin = (f64::from(TRAY_POPOVER_LOGICAL_X_MARGIN) * scale_factor).round() as i32;
    let y_margin = (f64::from(TRAY_POPOVER_LOGICAL_Y_MARGIN) * scale_factor).round() as i32;

    let mut popover_x = tray_x
        .saturating_add(tray_width)
        .saturating_sub(popover_w)
        .saturating_sub(x_margin);
    let monitor_width = saturating_u32_to_i32(monitor_size.width);
    let monitor_height = saturating_u32_to_i32(monitor_size.height);
    let min_x = monitor_pos.x;
    let min_y = monitor_pos.y;
    let max_x = monitor_pos
        .x
        .saturating_add(monitor_width)
        .saturating_sub(popover_w)
        .max(min_x);
    let max_y = monitor_pos
        .y
        .saturating_add(monitor_height)
        .saturating_sub(popover_h)
        .max(min_y);
    let below_y = tray_y.saturating_add(tray_height).saturating_add(y_margin);
    let above_y = tray_y.saturating_sub(popover_h).saturating_sub(y_margin);
    let monitor_mid_y = monitor_pos.y.saturating_add(monitor_height / 2);
    let preferred_y = if tray_y > monitor_mid_y {
        above_y
    } else {
        below_y
    };
    let alternate_y = if preferred_y == below_y {
        above_y
    } else {
        below_y
    };

    popover_x = popover_x.clamp(min_x, max_x);
    let popover_y = if (min_y..=max_y).contains(&preferred_y) {
        preferred_y
    } else if (min_y..=max_y).contains(&alternate_y) {
        alternate_y
    } else {
        preferred_y.clamp(min_y, max_y)
    };

    (popover_x, popover_y)
}

#[cfg(test)]
mod tests {
    use super::clamp_tray_popover_position_to_monitor;

    // Tests use scale_factor=1.0 so logical and physical dimensions match.
    #[test]
    fn tray_popover_prefers_below_when_space_exists() {
        let (x, y) = clamp_tray_popover_position_to_monitor(
            1380,
            10,
            20,
            20,
            tauri::PhysicalPosition::new(0, 0),
            tauri::PhysicalSize::new(1440, 900),
            1.0,
        );

        assert_eq!((x, y), (1012, 36));
    }

    #[test]
    fn tray_popover_flips_above_when_lower_space_overflows() {
        let (x, y) = clamp_tray_popover_position_to_monitor(
            1200,
            850,
            20,
            20,
            tauri::PhysicalPosition::new(0, 0),
            tauri::PhysicalSize::new(1440, 900),
            1.0,
        );

        assert_eq!((x, y), (832, 424));
    }

    #[test]
    fn tray_popover_clamps_to_monitor_when_monitor_is_smaller_than_popover() {
        let (x, y) = clamp_tray_popover_position_to_monitor(
            100,
            100,
            20,
            20,
            tauri::PhysicalPosition::new(40, 50),
            tauri::PhysicalSize::new(320, 300),
            1.0,
        );

        assert_eq!((x, y), (40, 50));
    }

    // Retina display: scale_factor=2.0, physical coordinates are 2x logical.
    // Tray at physical (2760, 20) on a 2880x1800 physical monitor.
    // Popover physical size = 380*2=760 x 420*2=840.
    #[test]
    fn tray_popover_retina_display_correct_position() {
        let (x, y) = clamp_tray_popover_position_to_monitor(
            2760,
            20,
            40,
            40,
            tauri::PhysicalPosition::new(0, 0),
            tauri::PhysicalSize::new(2880, 1800),
            2.0,
        );

        // popover_x = 2760 + 40 - 760 - 16 = 2024, clamped to [0, 2120] → 2024
        // below_y = 20 + 40 + 12 = 72, within [0, 960] → 72
        assert_eq!((x, y), (2024, 72));
    }

    // Multi-monitor: secondary monitor offset at physical (2880, 0).
    #[test]
    fn tray_popover_secondary_monitor_clamped() {
        let (x, y) = clamp_tray_popover_position_to_monitor(
            5700,
            20,
            40,
            40,
            tauri::PhysicalPosition::new(2880, 0),
            tauri::PhysicalSize::new(2880, 1800),
            2.0,
        );

        // popover_x = 5700 + 40 - 760 - 16 = 4964, clamped to [2880, 5000] → 4964
        // below_y = 72, within [0, 960] → 72
        assert_eq!((x, y), (4964, 72));
    }

    #[test]
    fn rect_to_physical_bounds_saturates_overflowing_physical_dimensions() {
        let bounds = super::rect_to_physical_bounds(tauri::Rect {
            position: tauri::Position::Physical(tauri::PhysicalPosition::new(12, 18)),
            size: tauri::Size::Physical(tauri::PhysicalSize::new(u32::MAX, u32::MAX)),
        });

        assert_eq!(bounds, (12, 18, i32::MAX, i32::MAX));
    }

    #[test]
    fn tray_popover_clamp_handles_overflowing_monitor_dimensions() {
        let (x, y) = clamp_tray_popover_position_to_monitor(
            180,
            220,
            24,
            24,
            tauri::PhysicalPosition::new(10, 20),
            tauri::PhysicalSize::new(u32::MAX, u32::MAX),
            1.0,
        );

        assert_eq!((x, y), (10, 250));
    }
}
