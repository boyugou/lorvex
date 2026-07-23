use super::WindowsCalendarSyncResult;
use crate::error::AppResult;

#[cfg(target_os = "windows")]
pub(super) fn record_permission_denied() -> AppResult<()> {
    crate::platform::provider_scope_state::record_permission_denied("windows_appointments", "")
}
#[cfg(target_os = "windows")]
pub(super) fn denied_result(error: &str) -> WindowsCalendarSyncResult {
    WindowsCalendarSyncResult {
        events_imported: 0,
        events_updated: 0,
        events_removed: 0,
        calendars_scanned: 0,
        available: true,
        error: Some(error.to_string()),
    }
}

/// Classify an `AppointmentManager::RequestStoreAsync` failure into
/// a user-visible cause string. A single generic "Calendar access
/// denied" toast would conflate three distinct failures — broker
/// stalled, user declined the consent prompt, and Group Policy
/// disabled the calendar broker entirely — even though their
/// remediations are different:
///
/// - **User declined / not granted (`E_ACCESSDENIED` / `0x80070005`)**
///   — direct the user to *Settings → Privacy & Security → Calendar*
///   to flip the per-app permission switch.
/// - **Group Policy / MDM disabled (`UAC_DISABLED` family /
///   `RPC_E_DISCONNECTED` / `0x800704B1` "no network",
///   `0x80070032` "not supported", or any HRESULT whose facility is
///   `FACILITY_GROUP_POLICY = 0x14`)** — surface the GP origin
///   so an enterprise user knows to escalate to their admin.
/// - **Broker stalled / timed out** — handled in the calling
///   `Err(AppError::Timeout)` arm; this helper only categorizes
///   synchronous WinRT errors.
/// - **Anything else** — fall back to the generic message but
///   include the raw HRESULT for diagnostics.
///
/// The strings are intentionally distinct so Settings → Diagnostics
/// (the error_logs surface) can show the user the right next step
/// instead of the same opaque blob for every failure mode.
#[cfg(target_os = "windows")]
pub(super) fn classify_request_store_error(err: &windows::core::Error) -> String {
    let hresult = err.code();
    let raw = hresult.0 as u32;

    // E_ACCESSDENIED — the canonical "user said no" / "policy
    // forbids it" code returned by the WinRT consent broker. The
    // remediation is per-app permission in Settings.
    const E_ACCESSDENIED: u32 = 0x8007_0005;
    // ERROR_NOT_SUPPORTED (0x32) wrapped in the Win32 facility —
    // Windows Server / LTSC SKUs without the People app return
    // this when the AppointmentStore is fundamentally unavailable
    // on the SKU.
    const E_NOT_SUPPORTED_WIN32: u32 = 0x8007_0032;
    // FACILITY_GROUP_POLICY (0x14) — any HRESULT whose facility
    // bits are 0x14 originated in a Group Policy enforcement
    // path. Mask: bits 16..27 carry the facility.
    const FACILITY_GROUP_POLICY: u32 = 0x14;

    let facility = (raw >> 16) & 0x1FFF;

    if raw == E_ACCESSDENIED {
        return format!(
            "Calendar access not granted. Open Windows Settings → \
             Privacy & Security → Calendar and enable access for \
             Lorvex, then try again. (HRESULT 0x{raw:08X})"
        );
    }
    if facility == FACILITY_GROUP_POLICY || raw == E_NOT_SUPPORTED_WIN32 {
        return format!(
            "Calendar access is disabled by Group Policy or \
             unavailable on this Windows edition. Contact your \
             IT administrator to allow Calendar access for \
             Lorvex. (HRESULT 0x{raw:08X})"
        );
    }
    format!("Failed to open Windows Calendar store (HRESULT 0x{raw:08X}): {err}")
}
