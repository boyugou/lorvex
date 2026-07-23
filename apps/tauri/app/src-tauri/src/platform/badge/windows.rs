//! Windows: render a small overlay icon with the badge count and
//! set it on the taskbar button via `ITaskbarList3::SetOverlayIcon`.
//!
//! Dispatches the entire COM / GDI sequence onto the main thread.
//! `ITaskbarList3` is STA-affined and `SetOverlayIcon` returns
//! `RPC_E_WRONG_THREAD` when invoked from a thread that doesn't
//! own the target window. Tauri IPC runs on a worker pool, so
//! marshalling onto the main thread up front makes the
//! "called on the right thread" invariant hold deterministically.
//!
//! GDI resource discipline: every DIB section / DC / brush /
//! HICON is paired with its `DeleteObject` / `DeleteDC` /
//! `DestroyIcon` cleanup before the function returns. The icon
//! size scales with the per-monitor DPI of the owning window so
//! the badge stays crisp on 4K @ 200% scaling.

pub(crate) fn set_count(count: Option<i64>, app: &tauri::AppHandle) -> Result<(), String> {
    // marshal the COM/GDI sequence onto the
    // main thread so `ITaskbarList3::SetOverlayIcon` is invoked from
    // the window's owning thread. Tauri's IPC pool does NOT own the
    // main HWND; calling SetOverlayIcon from a worker thread can
    // surface as `RPC_E_WRONG_THREAD` under stress (many badge
    // updates per second). Fire-and-forget: a transient main-thread
    // failure lands in error_logs via `log_set_count_failure`. The
    // dispatcher itself only fails when the runtime is shutting
    // down, which is reported back to the caller.
    let app_for_closure = app.clone();
    app.run_on_main_thread(move || {
        if let Err(err) = set_count_on_main_thread(count, &app_for_closure) {
            log_set_count_failure(&err);
        }
    })
    .map_err(|e| format!("badge: failed to dispatch to main thread: {e}"))?;

    Ok(())
}

fn log_set_count_failure(detail: &str) {
    if let Ok(conn) = crate::db::get_conn() {
        let _ = crate::commands::diagnostics::append_error_log_internal(
            &conn,
            "platform.badge",
            detail,
            None,
            Some("warn".to_string()),
        );
    }
}

fn set_count_on_main_thread(count: Option<i64>, app: &tauri::AppHandle) -> Result<(), String> {
    use raw_window_handle::HasWindowHandle;
    use std::ptr;
    use tauri::Manager;
    use windows::core::PCWSTR;
    use windows::Win32::Graphics::Gdi::{
        CreateCompatibleDC, CreateDIBSection, CreateFontW, DeleteDC, DeleteObject, DrawTextW,
        SelectObject, SetBkMode, SetTextColor, BITMAPINFO, BITMAPINFOHEADER, CLEARTYPE_QUALITY,
        CLIP_DEFAULT_PRECIS, COLORREF, DEFAULT_CHARSET, DEFAULT_PITCH, DIB_RGB_COLORS, DT_CENTER,
        DT_NOPREFIX, DT_SINGLELINE, DT_VCENTER, FF_SWISS, FW_BOLD, HGDIOBJ, OUT_DEFAULT_PRECIS,
        TRANSPARENT,
    };
    use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_INPROC_SERVER};

    use super::com_apartment::ComApartmentGuard;
    use windows::Win32::UI::Shell::{ITaskbarList, ITaskbarList3};
    use windows::Win32::UI::WindowsAndMessaging::{
        CreateIconIndirect, DestroyIcon, HICON, ICONINFO,
    };

    // --- Obtain HWND from the main window ---
    let main_window = app
        .get_webview_window("main")
        .ok_or_else(|| "badge: main window not found".to_string())?;

    let window_handle = main_window
        .window_handle()
        .map_err(|e| format!("badge: failed to get window handle: {e}"))?;

    let raw = window_handle.as_raw();
    let hwnd = match raw {
        raw_window_handle::RawWindowHandle::Win32(h) => {
            windows::Win32::Foundation::HWND(h.hwnd.get() as *mut _)
        }
        _ => return Err("badge: unexpected window handle type (not Win32)".to_string()),
    };

    // --- Initialize COM (no-op if already initialized on this thread) ---
    //
    // The guard pairs the CoInitializeEx lifecycle correctly: owned
    // -> Drop calls CoUninitialize; borrowed (S_FALSE /
    // RPC_E_CHANGED_MODE) -> Drop is a no-op. Discarding the HRESULT
    // would leak an apartment registration on Tauri's pooled IPC
    // threads on every successful `CoInitializeEx(S_OK)` that never
    // got a matching `CoUninitialize`.
    //
    // bail out when the apartment is borrowed in a
    // *different* model (`RPC_E_CHANGED_MODE` from `CoInitializeEx`).
    // `ITaskbarList3` is STA-affined; proceeding into the COM calls
    // when the thread already lives in an MTA produces non-deterministic
    // failures (the `IShellLinkW` cocreate may still succeed via the
    // agile-proxy fast-path and crash later inside `SetOverlayIcon`).
    // After M8 we run on the main thread, which Tauri configures as
    // STA — but defense-in-depth: if the precondition ever breaks, we
    // surface a deterministic error instead of a flaky crash.
    let _com_guard = ComApartmentGuard::enter_sta();
    if !_com_guard.is_in_sta() {
        return Err(
            "badge: main thread is not in an STA apartment; cannot call STA-affined \
             ITaskbarList3 (the thread was previously initialized as MTA)"
                .to_string(),
        );
    }

    // --- Create ITaskbarList3 ---
    // SAFETY: COM call inside the apartment
    // owned by `_com_guard`; the CLSID is the documented shell
    // singleton and the typed `windows-rs` wrapper handles the
    // returned `IUnknown` lifetime via `Retained<_>`.
    let taskbar: ITaskbarList3 = unsafe {
        CoCreateInstance(
            &windows::Win32::UI::Shell::TaskbarList,
            None,
            CLSCTX_INPROC_SERVER,
        )
        .map_err(|e| format!("badge: failed to create ITaskbarList3: {e}"))?
    };

    // ITaskbarList3 inherits from ITaskbarList, which requires HrInit() to be
    // called before any other methods. Without this, SetOverlayIcon may silently
    // fail or produce undefined behavior on some Windows versions.
    // SAFETY: `taskbar` is a live COM pointer
    // owned via `Retained<_>`; `cast` and `HrInit` are typed
    // `windows-rs` wrappers that require only a live receiver.
    unsafe {
        let taskbar_base: ITaskbarList = taskbar
            .cast()
            .map_err(|e| format!("badge: failed to cast to ITaskbarList: {e}"))?;
        taskbar_base
            .HrInit()
            .map_err(|e| format!("badge: ITaskbarList::HrInit failed: {e}"))?;
    }

    let effective = count.filter(|v| *v > 0);

    if let Some(n) = effective {
        // --- Build a DPI-scaled overlay icon with the count ---
        //
        // Read the per-monitor DPI for the owning HWND and size the
        // icon at the matching physical pixel count so the shell can
        // blit 1:1. A hard-coded 16×16 (the logical-pixel size for
        // 96 DPI / 100% scale) would force the shell to stretch the
        // bitmap to 32×32 with bilinear filtering on a 4K display at
        // 200% scale — the badge would look blurry and the text
        // illegible. Use 16 *logical* pixels as the base (the stock
        // `SM_CXSMICON` for 96 DPI) and round to the nearest physical
        // pixel.
        //
        // SAFETY: `GetDpiForWindow` requires a valid HWND, which we
        // obtained above. It's the documented Per-Monitor V2 API
        // and is available since Windows 10 1607. On older builds
        // it returns 0, in which case we fall back to 96 DPI.
        let dpi = unsafe { windows::Win32::UI::HiDpi::GetDpiForWindow(hwnd) };
        let effective_dpi = if dpi == 0 { 96 } else { dpi };
        // Logical 16 → physical (16 * dpi / 96), clamp to a sane
        // range so we don't allocate a huge DIB section if the OS
        // reports a bogus DPI value.
        let icon_size: i32 = ((16u32 * effective_dpi) / 96).clamp(16, 128) as i32;

        // Every fallible step from `CreateCompatibleDC` through
        // `SetOverlayIcon` is wrapped in an inner closure with a
        // `BadgeGdiResources` Drop guard that deletes any GDI handle
        // still owned by the closure when it returns Err. Without
        // the guard, a `?` after creating `hbmp` but before
        // `CreateIconIndirect` would leak `hbmp` (and on the mask
        // path, the mask's own `?` would leak both `hbmp` and the
        // selected font). Under stress (every reminder
        // firing/clearing the badge) the GDI handle table (10k
        // handles per process) would exhaust and the entire app's
        // GDI subsystem would break — windows fail to repaint,
        // dialogs fail to render — while the badge timer keeps
        // retrying and locks in the failure state.
        //
        // Cleanup guard: every owned GDI handle goes through `Option`
        // slots; Drop runs on the way out and frees whatever is
        // still Some. The success path explicitly takes() each
        // handle when ownership is fully transferred (the handle has
        // been deleted ourselves or copied by the kernel) so Drop
        // sees None and does nothing. On any early return via `?`,
        // Drop frees what we still hold.
        //
        // The Drop guard also remembers the GDI objects already
        // selected into the HDC at entry (`old_bmp`, `old_font`) and
        // re-`SelectObject`s them before deleting our owned bitmap /
        // font. Per Microsoft's `DeleteObject` docs, "If the
        // specified handle is not valid or is currently selected
        // into a DC, the return value is zero" — and on some drivers
        // a leaked-but-still-selected GDI resource leads to
        // undefined behavior on the next draw. Both `Option<HGDIOBJ>`
        // slots are tracked and restored-then-deleted in the guard
        // so an early-return `?` between `SelectObject(hdc, hbmp/
        // font)` and the manual restore cannot leave the font / bmp
        // selected when Drop runs `DeleteObject` on it.
        struct BadgeGdiResources {
            hdc: Option<windows::Win32::Graphics::Gdi::HDC>,
            hbmp: Option<windows::Win32::Graphics::Gdi::HBITMAP>,
            hmask: Option<windows::Win32::Graphics::Gdi::HBITMAP>,
            font: Option<windows::Win32::Graphics::Gdi::HFONT>,
            hicon: Option<HICON>,
            /// SelectObject return value for the bitmap slot —
            /// previously-selected default bitmap. Restored before
            /// the owned bitmap is deleted to satisfy the GDI
            /// "selected objects must not be deleted" contract.
            old_bmp: Option<HGDIOBJ>,
            /// Same contract as `old_bmp` for the font slot.
            old_font: Option<HGDIOBJ>,
        }
        impl Drop for BadgeGdiResources {
            fn drop(&mut self) {
                // SAFETY: each handle slot is
                // populated only after a successful GDI create call
                // earlier in this function; on Drop we own the
                // outstanding handles. `SelectObject` needs a live
                // HDC (we hold the slot), `DeleteObject` accepts any
                // GDI handle (typed via the `windows-rs` `HGDIOBJ`
                // newtype), `DeleteDC` requires a live HDC, and
                // `DestroyIcon` consumes a live HICON. The
                // restore-then-delete order honors the GDI contract
                // that selected objects must not be deleted while
                // selected.
                unsafe {
                    // Restore the original font into the HDC before
                    // deleting our font. SelectObject is idempotent
                    // on a valid HGDIOBJ; the old object pointer
                    // came from a SelectObject we already performed,
                    // so it is guaranteed valid for the lifetime of
                    // the HDC.
                    if let (Some(hdc), Some(old_font)) = (self.hdc, self.old_font.take()) {
                        let _ = SelectObject(hdc, old_font);
                    }
                    if let Some(font) = self.font.take() {
                        let _ = DeleteObject(HGDIOBJ(font.0 as *mut _));
                    }
                    // Same restore-then-delete pattern for the
                    // bitmap slot.
                    if let (Some(hdc), Some(old_bmp)) = (self.hdc, self.old_bmp.take()) {
                        let _ = SelectObject(hdc, old_bmp);
                    }
                    if let Some(hbmp) = self.hbmp.take() {
                        let _ = DeleteObject(HGDIOBJ(hbmp.0 as *mut _));
                    }
                    if let Some(hmask) = self.hmask.take() {
                        let _ = DeleteObject(HGDIOBJ(hmask.0 as *mut _));
                    }
                    if let Some(hdc) = self.hdc.take() {
                        let _ = DeleteDC(hdc);
                    }
                    if let Some(hicon) = self.hicon.take() {
                        let _ = DestroyIcon(hicon);
                    }
                }
            }
        }
        let mut gdi = BadgeGdiResources {
            hdc: None,
            hbmp: None,
            hmask: None,
            font: None,
            hicon: None,
            old_bmp: None,
            old_font: None,
        };

        // SAFETY: the entire GDI sequence runs
        // with the `gdi: BadgeGdiResources` Drop guard tracking every
        // owned handle. Every GDI call has its preconditions
        // verified before the next: `CreateCompatibleDC` is followed
        // by an `is_invalid()` check; `CreateDIBSection` is `?`-
        // propagated and the resulting `bits_ptr` is null-checked
        // before the slice is materialized over a known-valid
        // `pixel_count` length; `SelectObject` calls have their
        // returned previously-selected objects stashed in the guard
        // for the documented restore-then-delete cleanup; the
        // `slice::from_raw_parts_mut` covers exactly
        // `icon_size * icon_size` `u32` slots that the OS
        // initialized (32-bit DIB section). On any `?`-propagated
        // failure the Drop guard cleans up the partial state.
        unsafe {
            // Create a memory DC
            let hdc = CreateCompatibleDC(None);
            if hdc.is_invalid() {
                return Err("badge: CreateCompatibleDC failed".to_string());
            }
            gdi.hdc = Some(hdc);

            // Create a 32-bit DIB section (required for alpha in HICON).
            // BI_RGB = uncompressed. biHeight is negative for top-down layout.
            let mut bmi = BITMAPINFO::default();
            bmi.bmiHeader.biSize = std::mem::size_of::<BITMAPINFOHEADER>() as u32;
            bmi.bmiHeader.biWidth = icon_size;
            bmi.bmiHeader.biHeight = -icon_size; // top-down DIB
            bmi.bmiHeader.biPlanes = 1;
            bmi.bmiHeader.biBitCount = 32;
            // biCompression = BI_RGB (0) — already zero from Default

            let mut bits_ptr: *mut std::ffi::c_void = ptr::null_mut();
            let hbmp = CreateDIBSection(hdc, &bmi, DIB_RGB_COLORS, &mut bits_ptr, None, 0)
                .map_err(|e| format!("badge: CreateDIBSection failed: {e}"))?;
            gdi.hbmp = Some(hbmp);

            // `CreateDIBSection` can succeed and return a non-null `HBITMAP`
            // while leaving `bits_ptr` null in pathological paths (e.g. GDI
            // out-of-memory, closed section handle). Slicing a null pointer
            // via `from_raw_parts_mut` is instant undefined behavior, so
            // gate the downstream paint loop on a non-null pointer check.
            if bits_ptr.is_null() {
                return Err("badge: CreateDIBSection returned null bits pointer".into());
            }

            // Track the previously-selected bitmap in the cleanup
            // guard so Drop can restore it before calling
            // DeleteObject on our owned `hbmp`. Discarding the
            // SelectObject return value would let an early `?`
            // between this line and the manual `SelectObject(hdc,
            // old_bmp)` restore further down leave `hbmp` selected
            // into the DC when Drop runs DeleteObject on it.
            let old_bmp = SelectObject(hdc, HGDIOBJ(hbmp.0 as *mut _));
            gdi.old_bmp = Some(old_bmp);

            // Paint a red circle with per-pixel alpha.
            // DIB pixel layout in memory: B, G, R, A (four bytes).
            // As a little-endian u32: 0xAA_RR_GG_BB.
            let pixel_count = (icon_size * icon_size) as usize;
            // assert the DIB section's bits
            // pointer is `u32`-aligned before we materialize a
            // `&mut [u32]` over it. `CreateDIBSection` for 32-bpp
            // DIB pixels returns a 4-byte-aligned buffer per the
            // GDI contract — but a debug_assert here turns any
            // future driver / virtualized-GDI surprise into a
            // panic instead of silent UB. Production behavior is
            // unchanged because debug_assert! is a no-op in
            // release builds.
            debug_assert_eq!(
                (bits_ptr as usize) % std::mem::align_of::<u32>(),
                0,
                "badge: DIB section bits pointer is not u32-aligned",
            );
            let pixels = std::slice::from_raw_parts_mut(bits_ptr as *mut u32, pixel_count);

            let center = icon_size as f32 / 2.0;
            let radius = center;
            let red_pixel: u32 = 0xFF_DD_00_00; // #DD0000, fully opaque
            let clear_pixel: u32 = 0x00_00_00_00;
            for y in 0..icon_size {
                for x in 0..icon_size {
                    let dx = x as f32 + 0.5 - center;
                    let dy = y as f32 + 0.5 - center;
                    let idx = (y * icon_size + x) as usize;
                    pixels[idx] = if dx * dx + dy * dy <= radius * radius {
                        red_pixel
                    } else {
                        clear_pixel
                    };
                }
            }

            // Draw the count text in white with a small bold font
            SetBkMode(hdc, TRANSPARENT);
            SetTextColor(hdc, COLORREF(0x00_FF_FF_FF)); // white (BGR)

            // Create a small font for the badge text. Without this, Windows
            // uses the default system font which is too large for the icon.
            // scale the font height with the icon size
            // so the digits don't get smaller relative to the badge on
            // high-DPI hosts (we're rendering at physical pixels, not
            // logical pixels — see the icon_size DPI math above).
            let font_height = ((icon_size as i32) * 10) / 16;
            let font = CreateFontW(
                font_height,
                0,
                0,
                0,
                FW_BOLD.0 as i32,
                0,
                0,
                0,
                DEFAULT_CHARSET.0 as u32,
                OUT_DEFAULT_PRECIS.0 as u32,
                CLIP_DEFAULT_PRECIS.0 as u32,
                CLEARTYPE_QUALITY.0 as u32,
                (DEFAULT_PITCH.0 | FF_SWISS.0) as u32,
                windows::core::w!("Segoe UI"),
            );
            gdi.font = Some(font);
            // stash the previously-selected font for
            // the Drop-guard restore path; same contract as the
            // bitmap slot above.
            let old_font = SelectObject(hdc, HGDIOBJ(font.0 as *mut _));
            gdi.old_font = Some(old_font);

            let label = if n > 99 {
                "99+".to_string()
            } else {
                n.to_string()
            };
            let mut wide: Vec<u16> = label.encode_utf16().collect();

            let mut rc = windows::Win32::Foundation::RECT {
                left: 0,
                top: 0,
                right: icon_size,
                bottom: icon_size,
            };

            DrawTextW(
                hdc,
                &mut wide,
                &mut rc,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX,
            );

            // Restore the original font and free it eagerly (text already
            // rasterized into the bitmap; the font handle is no longer
            // needed). Take it AND its `old_font` slot out of the
            // cleanup guard so Drop doesn't double-restore or
            // double-free.
            SelectObject(hdc, old_font);
            gdi.old_font.take();
            if let Some(font) = gdi.font.take() {
                let _ = DeleteObject(HGDIOBJ(font.0 as *mut _));
            }

            // Create a monochrome AND-mask (all zeros = fully visible).
            // For 32-bit color bitmaps with alpha, the AND-mask should be
            // all-zero so the alpha channel in the color bitmap is honored.
            let mut mask_bmi = BITMAPINFO::default();
            mask_bmi.bmiHeader.biSize = std::mem::size_of::<BITMAPINFOHEADER>() as u32;
            mask_bmi.bmiHeader.biWidth = icon_size;
            mask_bmi.bmiHeader.biHeight = -icon_size;
            mask_bmi.bmiHeader.biPlanes = 1;
            mask_bmi.bmiHeader.biBitCount = 1;
            // biCompression = BI_RGB (0) — already zero from Default

            let mut mask_bits: *mut std::ffi::c_void = ptr::null_mut();
            let hmask = CreateDIBSection(hdc, &mask_bmi, DIB_RGB_COLORS, &mut mask_bits, None, 0)
                .map_err(|e| format!("badge: mask CreateDIBSection failed: {e}"))?;
            gdi.hmask = Some(hmask);

            // mask_bits is already zeroed by CreateDIBSection

            // Build ICONINFO and create the icon
            let mut icon_info = ICONINFO {
                fIcon: true.into(),
                xHotspot: 0,
                yHotspot: 0,
                hbmMask: hmask,
                hbmColor: hbmp,
            };

            let hicon = CreateIconIndirect(&mut icon_info)
                .map_err(|e| format!("badge: CreateIconIndirect failed: {e}"))?;
            gdi.hicon = Some(hicon);

            // Restore DC state. The bitmaps are referenced by the icon
            // handle now, but `CreateIconIndirect` makes a deep copy per
            // MSDN, so deleting our copies is correct. Take both the
            // owned bitmap AND its `old_bmp` slot out of the cleanup
            // guard since we're freeing them ourselves; otherwise
            // Drop would double-restore.
            SelectObject(hdc, old_bmp);
            gdi.old_bmp.take();
            if let Some(hbmp) = gdi.hbmp.take() {
                let _ = DeleteObject(HGDIOBJ(hbmp.0 as *mut _));
            }
            if let Some(hmask) = gdi.hmask.take() {
                let _ = DeleteObject(HGDIOBJ(hmask.0 as *mut _));
            }
            if let Some(hdc) = gdi.hdc.take() {
                DeleteDC(hdc).map_err(|e| format!("badge: DeleteDC failed: {e}"))?;
            }

            // Set the overlay icon on the taskbar. If this fails the
            // cleanup guard's `hicon` slot is still Some, so Drop will
            // call `DestroyIcon` for us.
            taskbar
                .SetOverlayIcon(hwnd, hicon, PCWSTR::null())
                .map_err(|e| format!("badge: SetOverlayIcon failed: {e}"))?;

            // The shell copies the icon internally; we can destroy our
            // copy. Take it from the guard since we're freeing it.
            if let Some(hicon) = gdi.hicon.take() {
                let _ = DestroyIcon(hicon);
            }
        }
    } else {
        // Clear the overlay by passing a default (null) icon handle.
        // SAFETY: `taskbar` is a live COM
        // pointer; passing a null `HICON` is the documented way to
        // clear an overlay icon per
        // `ITaskbarList3::SetOverlayIcon` MSDN.
        unsafe {
            taskbar
                .SetOverlayIcon(hwnd, HICON::default(), PCWSTR::null())
                .map_err(|e| format!("badge: clear SetOverlayIcon failed: {e}"))?;
        }
    }

    Ok(())
}
