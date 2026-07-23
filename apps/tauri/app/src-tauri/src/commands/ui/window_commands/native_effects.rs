//! Native window backdrop effects (Windows 11 Mica + immersive
//! dark-mode title bar). On every other platform this module's
//! single IPC entry point is a no-op.

#[cfg(target_os = "windows")]
use tauri::Manager;

/// Probe whether the current host is Windows 11 (build >= 22000) using
/// the real OS version reported by `RtlGetVersion` (ntdll), which —
/// unlike `GetVersionExW` — is not subject to the application
/// compatibility shim that lies about the version on unmanifested
/// binaries. `set_native_window_effects` gates on this probe before
/// requesting `Effect::Mica`: `DwmExtendFrameIntoClientArea` + the
/// Mica material APIs only exist on Win11 (≥22000), so requesting
/// Mica on Win10 would produce a hard error from Tauri's effect
/// builder that the theme picker would surface as a failure toast.
/// Roughly 30% of the Windows install base is still on Win10 (per
/// StatCounter), so this code path silently downgrades to default
/// chrome on Win10 — the user keeps a working window and the
/// renderer's CSS theme tokens still render the visual style
/// correctly.
#[cfg(target_os = "windows")]
fn is_windows_11_or_greater() -> bool {
    use windows::Wdk::System::SystemServices::RtlGetVersion;
    use windows::Win32::Foundation::STATUS_SUCCESS;
    use windows::Win32::System::SystemInformation::OSVERSIONINFOW;

    // SAFETY: `RtlGetVersion` writes into a stack-allocated
    // `OSVERSIONINFOW` whose `dwOSVersionInfoSize` we initialize per
    // the documented contract. ntdll is always loaded in a Win32
    // process; the call has no preconditions beyond the size field.
    let mut info = OSVERSIONINFOW {
        dwOSVersionInfoSize: std::mem::size_of::<OSVERSIONINFOW>() as u32,
        ..Default::default()
    };
    let status = unsafe { RtlGetVersion(&mut info) };
    if status != STATUS_SUCCESS {
        // Fail closed: if we can't read the version, assume the host
        // does NOT support Mica. Worse to crash a Win10 user with a
        // hard-erroring effect call than to skip the eye candy on a
        // host that might actually be Win11.
        return false;
    }
    // Windows 11 starts at NT 10.0 build 22000. The major/minor stay
    // at 10.0 (Microsoft kept the version number for compatibility);
    // the build number is the only reliable discriminator.
    info.dwMajorVersion > 10 || (info.dwMajorVersion == 10 && info.dwBuildNumber >= 22000)
}

/// apply the immersive-dark-mode DWM attribute
/// to the window's non-client area. The attribute number is `20` on
/// Windows 10 1809 (10.0.17763) and `20`/`19` on older 1903 betas;
/// the `windows-rs` crate exposes the canonical value through the
/// `DWMWA_USE_IMMERSIVE_DARK_MODE` constant.
///
/// `DwmSetWindowAttribute` accepts a `BOOL` payload by pointer; we
/// pass `1` for dark and `0` for light. On platforms that don't
/// understand the attribute (Windows 10 < 1809, Windows Server LTSC
/// SKUs without the desktop window manager) DWM returns a non-S_OK
/// HRESULT and we silently swallow it — the title bar simply stays
/// light, which is the default DWM rendering on those SKUs.
#[cfg(target_os = "windows")]
fn apply_immersive_dark_title_bar(window: &tauri::WebviewWindow, is_dark: bool) {
    use raw_window_handle::HasWindowHandle;
    use windows::Win32::Foundation::{BOOL, HWND};
    use windows::Win32::Graphics::Dwm::{DwmSetWindowAttribute, DWMWA_USE_IMMERSIVE_DARK_MODE};

    let Ok(handle) = window.window_handle() else {
        return;
    };
    let raw = handle.as_raw();
    let raw_window_handle::RawWindowHandle::Win32(h) = raw else {
        return;
    };
    let hwnd = HWND(h.hwnd.get() as *mut _);
    // `BOOL` is a typed alias for `i32`; the DWM contract takes 1 for
    // "dark" / 0 for "light". Use `BOOL::from(bool)` rather than a
    // raw cast so the wrapper handles future representational changes.
    let value: BOOL = BOOL::from(is_dark);
    // SAFETY: `DwmSetWindowAttribute` is the documented entry point
    // for setting per-window DWM attributes. The HWND is alive for
    // the duration of this call (we hold a `WebviewWindow`
    // reference). The size argument matches the BOOL we point at.
    unsafe {
        let _ = DwmSetWindowAttribute(
            hwnd,
            DWMWA_USE_IMMERSIVE_DARK_MODE,
            &value as *const BOOL as *const std::ffi::c_void,
            std::mem::size_of::<BOOL>() as u32,
        );
    }
}

/// Apply native window backdrop effects based on the active theme.
///
/// On Windows 11, Mica themes apply the real Mica material behind the WebView.
/// The frontend must also set a transparent `<html>` background so the native
/// material shows through. On Windows 10 the Mica APIs (`DwmExtendFrameIntoClientArea`
/// + `DWMWA_SYSTEMBACKDROP_TYPE`) hard-error, so this command silently
/// downgrades to the default chrome there. On other platforms this is a no-op.
#[tauri::command]
pub fn set_native_window_effects(app: tauri::AppHandle, theme: String) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        use tauri::window::{Effect, EffectsBuilder};

        let is_mica = theme == "mica" || theme == "mica_light";
        let is_dark = matches!(theme.as_str(), "mica" | "dark" | "darcula" | "nord");

        if let Some(window) = app.get_webview_window("main") {
            // gate Mica behind a Windows 11
            // runtime probe. On Win10 the underlying DWM calls
            // (`DwmExtendFrameIntoClientArea`,
            // `DWMWA_SYSTEMBACKDROP_TYPE`) are unimplemented and
            // Tauri propagates the HRESULT as a hard error to the
            // theme picker. Soft-fall to default chrome instead so
            // the picker can continue selecting Mica-named themes
            // (the renderer still resolves the right CSS variables);
            // we just skip the native material request.
            if is_mica && is_windows_11_or_greater() {
                let effects = EffectsBuilder::new().effect(Effect::Mica).build();
                window
                    .set_effects(effects)
                    .map_err(|e| String::from(crate::error::AppError::from(e)))?;
            } else {
                // Clear native effects when switching away from Mica themes,
                // or when Mica was requested on Win10 (no-op fall-through).
                window
                    .set_effects(None::<tauri::utils::config::WindowEffectsConfig>)
                    .map_err(|e| String::from(crate::error::AppError::from(e)))?;
            }

            // apply
            // `DWMWA_USE_IMMERSIVE_DARK_MODE` so the non-client area
            // (title bar, borders, system menu chrome) tracks the
            // active theme. Without this, switching to a dark theme
            // left the title bar painted in the system light color —
            // a glaring mismatch that made the dark-mode UI look
            // half-finished. The attribute is the documented mechanism
            // since Windows 10 1809; on older builds the call is a
            // no-op (DWM rejects unknown attributes silently).
            apply_immersive_dark_title_bar(&window, is_dark);
        }

        Ok(())
    }

    #[cfg(not(target_os = "windows"))]
    {
        let _ = (app, theme);
        Ok(())
    }
}
