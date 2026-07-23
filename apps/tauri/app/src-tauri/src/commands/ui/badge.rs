/// Maximum badge count rendered by any platform. Beyond this the overlay
/// becomes illegible (Windows taskbar overlay is 16×16 px, macOS dock
/// label degrades past ~3 digits) and a buggy renderer that submits a
/// huge `i64` would render gibberish or crash the GDI text path.
const MAX_BADGE_COUNT: i64 = 999;

/// Set the app badge count. Delegates to `platform::badge`.
///
/// clamp `count` at the IPC boundary to `0..=999`
/// before dispatching. Negative values map to `None` (clear the
/// badge). Values above the cap are pinned to `MAX_BADGE_COUNT` so
/// platform code can assume a renderable range and the renderer
/// can't push gigantic counts through the platform code.
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn set_badge_count(app: tauri::AppHandle, count: Option<i64>) -> Result<(), String> {
    let normalized = count.and_then(|n| {
        if n <= 0 {
            None
        } else {
            Some(n.min(MAX_BADGE_COUNT))
        }
    });
    crate::platform::badge::set_count(normalized, &app)
}

#[cfg(test)]
mod tests {
    use super::MAX_BADGE_COUNT;

    /// pin the canonical clamp logic so a refactor
    /// can't silently widen the range. The Tauri command's runtime
    /// path needs a real `AppHandle`, so the clamp is exercised
    /// here in pure form against the same constant the command uses.
    fn clamp(count: Option<i64>) -> Option<i64> {
        count.and_then(|n| {
            if n <= 0 {
                None
            } else {
                Some(n.min(MAX_BADGE_COUNT))
            }
        })
    }

    #[test]
    fn clamps_negative_to_none() {
        assert_eq!(clamp(Some(-1)), None);
        assert_eq!(clamp(Some(i64::MIN)), None);
    }

    #[test]
    fn clamps_zero_to_none() {
        assert_eq!(clamp(Some(0)), None);
    }

    #[test]
    fn passes_through_normal_counts_unchanged() {
        assert_eq!(clamp(Some(1)), Some(1));
        assert_eq!(clamp(Some(50)), Some(50));
        assert_eq!(clamp(Some(MAX_BADGE_COUNT)), Some(MAX_BADGE_COUNT));
    }

    #[test]
    fn caps_oversize_to_max_badge_count() {
        assert_eq!(clamp(Some(MAX_BADGE_COUNT + 1)), Some(MAX_BADGE_COUNT));
        assert_eq!(clamp(Some(i64::MAX)), Some(MAX_BADGE_COUNT));
    }

    #[test]
    fn none_passes_through_as_none() {
        assert_eq!(clamp(None), None);
    }
}
