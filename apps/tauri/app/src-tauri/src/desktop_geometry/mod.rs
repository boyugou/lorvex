pub(crate) fn saturating_u32_to_i32(value: u32) -> i32 {
    i32::try_from(value).unwrap_or(i32::MAX)
}

#[cfg(test)]
pub(crate) fn saturating_usize_to_i32(value: usize) -> i32 {
    i32::try_from(value).unwrap_or(i32::MAX)
}

/// Axis-aligned monitor rectangle in physical pixels, expressed in the
/// same coordinate space Tauri reports for `outer_position` /
/// `outer_size`. Used by the multi-monitor clamp helper so the caller
/// can collect a `Monitor` slice without dragging the full `tauri::Monitor`
/// shape through internal helpers (and so the helper is unit-testable
/// without standing up a Tauri runtime).
#[cfg(desktop)]
#[derive(Clone, Copy, Debug)]
pub(crate) struct MonitorRect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[cfg(desktop)]
impl MonitorRect {
    pub fn from_tauri(monitor: &tauri::Monitor) -> Self {
        let pos = monitor.position();
        let size = monitor.size();
        Self {
            x: pos.x,
            y: pos.y,
            width: saturating_u32_to_i32(size.width),
            height: saturating_u32_to_i32(size.height),
        }
    }

    #[allow(dead_code)] // exercised through the retained clamp helper; production currently centers instead.
    const fn contains_point(&self, px: i32, py: i32) -> bool {
        let x_end = self.x.saturating_add(self.width);
        let y_end = self.y.saturating_add(self.height);
        px >= self.x && px < x_end && py >= self.y && py < y_end
    }
}

/// Clamp a desired window placement `(x, y)` of size `(width, height)`
/// onto the union of available monitors. Returns the clamped position.
///
/// Picks the monitor whose rect contains the requested top-left
/// corner; if no monitor contains the corner, centers the window on
/// `fallback` (typically the primary monitor). With no monitors at
/// all (headless / detached display) returns the input unchanged so
/// the caller's other guards still apply.
///
/// Window-placement call sites must route through this helper rather
/// than `.max(0)`-clamping against `(0, 0)` (which sends windows to
/// the top-left of the *primary* monitor on multi-monitor setups,
/// even when the user wanted a secondary display) or skipping
/// clamping entirely.
#[cfg(desktop)]
#[allow(dead_code)] // retained for tested multi-monitor placement; current restore path uses overlap checks.
pub(crate) fn clamp_to_visible_monitor(
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    monitors: &[MonitorRect],
    fallback: Option<MonitorRect>,
) -> tauri::PhysicalPosition<i32> {
    let margin: i32 = 12;

    let containing = monitors
        .iter()
        .find(|m| m.contains_point(x, y))
        .copied()
        .or(fallback)
        .or_else(|| monitors.first().copied());

    let Some(monitor) = containing else {
        return tauri::PhysicalPosition::new(x, y);
    };

    // If the window doesn't fit on the chosen monitor (very small
    // monitor / oversize requested window), pin to the monitor origin.
    if monitor.width <= width.saturating_add(margin.saturating_mul(2))
        || monitor.height <= height.saturating_add(margin.saturating_mul(2))
    {
        return tauri::PhysicalPosition::new(monitor.x, monitor.y);
    }

    let min_x = monitor.x.saturating_add(margin);
    let min_y = monitor.y.saturating_add(margin);
    let max_x = monitor
        .x
        .saturating_add(monitor.width)
        .saturating_sub(width)
        .saturating_sub(margin);
    let max_y = monitor
        .y
        .saturating_add(monitor.height)
        .saturating_sub(height)
        .saturating_sub(margin);

    tauri::PhysicalPosition::new(x.clamp(min_x, max_x), y.clamp(min_y, max_y))
}

/// Centered top-left for a window of size `(width, height)` on the
/// given monitor. Returns the monitor origin if the window is too
/// large to center safely.
#[cfg(desktop)]
pub(crate) const fn centered_position_on_monitor(
    monitor: MonitorRect,
    width: i32,
    height: i32,
) -> tauri::PhysicalPosition<i32> {
    if monitor.width <= width || monitor.height <= height {
        return tauri::PhysicalPosition::new(monitor.x, monitor.y);
    }
    tauri::PhysicalPosition::new(
        monitor.x.saturating_add((monitor.width - width) / 2),
        monitor.y.saturating_add((monitor.height - height) / 2),
    )
}

/// Whether `(x, y)` of size `(width, height)` is at least partially
/// inside the union of `monitors`. persisted geometry
/// can drift completely off-screen (monitor unplugged between sessions);
/// this is the cheap "is this still visible at all" predicate the
/// main-window restore path uses to decide whether to fall back to a
/// centered default.
#[cfg(desktop)]
pub(crate) fn rect_overlaps_any_monitor(
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    monitors: &[MonitorRect],
) -> bool {
    let rx_end = x.saturating_add(width);
    let ry_end = y.saturating_add(height);
    monitors.iter().any(|m| {
        let mx_end = m.x.saturating_add(m.width);
        let my_end = m.y.saturating_add(m.height);
        x < mx_end && rx_end > m.x && y < my_end && ry_end > m.y
    })
}

#[cfg(test)]
mod tests;
