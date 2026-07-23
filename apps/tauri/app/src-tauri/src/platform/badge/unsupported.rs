//! Linux + mobile: badge is a no-op for now.
//!
//! Linux desktop entries support a Unity launcher badge via
//! D-Bus, but no LSB-blessed cross-distro contract exists; until
//! we wire up a per-DE backend the safe answer is "do nothing".
//! Android delegate badge management to
//! `tauri-plugin-notification`'s built-in badge count, so the
//! application doesn't need a per-target implementation here.

/// Linux/mobile: badge is a no-op for now.

pub(crate) fn set_count(_count: Option<i64>, _app: &tauri::AppHandle) -> Result<(), String> {
    Ok(())
}
