//! `ICustomDestinationList` rebuild driver — the Win32 analogue of
//! macOS's `CSSearchableItemAttributeSet` builders. Owns the COM
//! apartment lifetime, the shell-link construction loop, and the
//! time-boxed availability circuit breaker that guards Lorvex
//! against repeatedly hammering a Shell Experience Host that has
//! gone away (explorer.exe restart, Windows Server LTSC without
//! the Shell Experience Host, restricted session contexts).

use std::sync::atomic::{AtomicU64, Ordering};

use windows::core::HSTRING;
use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_INPROC_SERVER};
use windows::Win32::UI::Shell::{
    DestinationList, EnumerableObjectCollection, ICustomDestinationList, IObjectCollection,
    IShellLinkW, ShellLink,
};

use crate::platform::com_apartment::ComApartmentGuard;

use super::{TaskRow, MAX_JUMP_LIST_ITEMS};

/// When `CoCreateInstance(DestinationList, …)` fails, the host
/// either has Jump Lists temporarily unavailable (during shell
/// restart on a normal desktop) or permanently unavailable (Windows
/// Server LTSC without Shell Experience Host, restricted session
/// contexts). Time-box the breaker to 5 minutes so a transient
/// outage auto-recovers (explorer.exe restarting after an Explorer
/// extension crash is routine); permanent unavailability re-trips
/// on the next rebuild attempt and pays the same one-shot log +
/// 5-min suppression cost. A process-permanent boolean breaker
/// would strand the user with no Jump List for the rest of the
/// launch after any transient outage, with no recovery short of
/// quitting Lorvex.
///
/// `UNAVAILABLE_UNTIL_UNIX` stores the wall-clock instant the
/// breaker auto-rearms; 0 means "not tripped". Reads are
/// monotonic-ish via `SystemTime::now()`; if the user manually
/// adjusts the clock backwards the breaker may suppress slightly
/// longer than 5 min, which is acceptable.
///
/// the load/store/swap below all use
/// `Ordering::Relaxed` on purpose. The atomic carries no
/// cross-thread happens-before contract — every reader does its
/// own `SystemTime::now()` comparison after the load, and every
/// writer derives `until` from a fresh `SystemTime::now()`. A
/// concurrent reader observing a stale value is bounded to one
/// extra retry-cycle worth of suppression; a concurrent
/// `swap` race only affects who emits the one-shot
/// "breaker tripped" log line, which is idempotent. We
/// considered upgrading to `Acquire/Release` for symmetry with
/// nearby code, but since there is no protected memory paired
/// with this flag the stronger ordering would buy nothing and
/// emit a needless `dmb ish` on aarch64 every call. Documented
/// here so the audit follow-up does not silently re-tighten
/// the ordering on the next pass.
const JUMP_LIST_UNAVAILABLE_TIMEOUT_SECS: u64 = 5 * 60;
static JUMP_LIST_UNAVAILABLE_UNTIL_UNIX: AtomicU64 = AtomicU64::new(0);

fn jump_list_breaker_tripped() -> bool {
    let until = JUMP_LIST_UNAVAILABLE_UNTIL_UNIX.load(Ordering::Relaxed);
    if until == 0 {
        return false;
    }
    let now = match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
        Ok(d) => d.as_secs(),
        // Clock skew before the epoch — extremely rare; treat
        // as still tripped to err on the side of suppression.
        Err(_) => return true,
    };
    if now < until {
        true
    } else {
        // Auto-rearm — clear the gate so the next call retries.
        JUMP_LIST_UNAVAILABLE_UNTIL_UNIX.store(0, Ordering::Relaxed);
        false
    }
}

fn trip_jump_list_breaker() -> bool {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let until = now + JUMP_LIST_UNAVAILABLE_TIMEOUT_SECS;
    // Returns true if this call is the one that tripped the
    // breaker (so the caller knows to write the one-shot log).
    let prev = JUMP_LIST_UNAVAILABLE_UNTIL_UNIX.swap(until, Ordering::Relaxed);
    prev == 0 || prev <= now
}

/// Rebuild the Windows Jump List with the current set of indexed tasks.
///
/// Uses `ICustomDestinationList` to add a "Recent Tasks" category containing
/// shell links. Each link points to the current executable with a
/// `--open-task <id>` argument so the deep-link handler can navigate to the
/// task. The description is set to the task title (+ optional list/due info).
pub(super) fn rebuild_jump_list(candidates: &[TaskRow]) {
    // Short-circuit if the breaker is tripped. The breaker
    // auto-rearms after `JUMP_LIST_UNAVAILABLE_TIMEOUT_SECS`, so a
    // routine event like explorer.exe restarting cannot leave the
    // Jump List dead for the rest of the app session.
    if jump_list_breaker_tripped() {
        return;
    }
    if let Err(e) = rebuild_jump_list_inner(candidates) {
        let msg = e.to_string();
        // `CLASS_NOT_REGISTERED` (0x80040154) and a few related
        // shell-unavailable HRESULTs mean no amount of retrying
        // will help; persistent failure modes that would
        // otherwise spam logs get the time-boxed circuit-breaker
        // treatment.
        //
        // Include the explorer-restart HRESULTs
        // (`RPC_E_DISCONNECTED` / `RPC_S_SERVER_UNAVAILABLE` /
        // `CO_E_OBJNOTCONNECTED`) in the breaker-trip set alongside
        // `CLASS_NOT_REGISTERED`. Explorer hosts the
        // CDestinationListClass, so an explorer.exe restart is the
        // most common reason `BeginList` fails; without these
        // codes, every subsequent reindex would crash again and
        // spam `error_logs` with the same message until the user
        // restarted the app. Tripping for
        // `JUMP_LIST_UNAVAILABLE_TIMEOUT_SECS` lets explorer
        // recover.
        const HRESULT_CLASS_NOT_REGISTERED: u32 = 0x8004_0154;
        const HRESULT_RPC_E_DISCONNECTED: u32 = 0x8001_0108;
        const HRESULT_RPC_E_SERVER_DIED: u32 = 0x8001_0012;
        const HRESULT_RPC_S_SERVER_UNAVAILABLE: u32 = 0x8007_06BA;
        const HRESULT_CO_E_OBJNOTCONNECTED: u32 = 0x8004_01FD;
        const HRESULT_RPC_E_CALL_FAILED: u32 = 0x8001_0100;
        let raw = e.code().0 as u32;
        let is_class_unregistered = matches!(
            raw,
            HRESULT_CLASS_NOT_REGISTERED
                | HRESULT_RPC_E_DISCONNECTED
                | HRESULT_RPC_E_SERVER_DIED
                | HRESULT_RPC_S_SERVER_UNAVAILABLE
                | HRESULT_CO_E_OBJNOTCONNECTED
                | HRESULT_RPC_E_CALL_FAILED
        );
        if is_class_unregistered {
            if trip_jump_list_breaker() {
                super::super::log_spotlight_warning(
                    "platform.jump_list_unavailable",
                    &format!(
                        "Windows Jump List unavailable on this host; rebuild attempts \
                             will be suppressed for the next {}s before automatically \
                             retrying. {msg}",
                        JUMP_LIST_UNAVAILABLE_TIMEOUT_SECS
                    ),
                );
            }
            return;
        }
        super::super::log_spotlight_error("Windows jump list rebuild failed", &msg);
    }
}

fn rebuild_jump_list_inner(candidates: &[TaskRow]) -> Result<(), windows::core::Error> {
    // pair CoInitializeEx with CoUninitialize via the
    // RAII guard. The guard's Drop fires CoUninitialize ONLY when we
    // owned the apartment lifecycle (S_OK from CoInitializeEx);
    // S_FALSE / RPC_E_CHANGED_MODE skip the uninit so we never
    // release someone else's registration. Hold the guard for the
    // full COM call sequence below.
    let _com_guard = ComApartmentGuard::enter_sta();
    // SAFETY: the entire COM-call sequence
    // below runs inside the COM apartment owned by `_com_guard`
    // (Drop fires `CoUninitialize` on scope exit). `windows-rs`
    // marks every COM `unsafe` because the underlying ABI is FFI;
    // the Rust-side invariants we maintain are: (a) all
    // `IUnknown` references are owned `Retained<_>` typed
    // wrappers that handle Release on drop; (b) `BeginList` /
    // `AppendCategory` / `CommitList` are called in the
    // documented order with non-null in-params; (c) the buffer
    // `buf` for `GetArguments` is mutable for the call's
    // duration. The HRESULT propagation via `?` aborts the
    // sequence cleanly on any underlying failure.
    unsafe {
        let dest_list: ICustomDestinationList =
            CoCreateInstance(&DestinationList, None, CLSCTX_INPROC_SERVER)?;

        let mut max_slots: u32 = 0;
        let removed: IObjectCollection =
            dest_list.BeginList::<IObjectCollection>(&mut max_slots)?;

        // Collect IDs of removed items so we don't re-add them.
        //
        // Slice to the first NUL before decoding the OS-provided
        // UTF-16 buffer. `String::from_utf16_lossy(&buf)` over the
        // entire 1024-element zero-init slice and a trailing
        // `trim_end_matches('\0')` would only strip the trailing run
        // of nulls and leave any embedded NUL (rare but possible
        // when the OS sentinel is mid-buffer) in place. Also strip
        // surrounding quotes after the prefix match so the quoted
        // form `--open-task "<id>"` matches; pinned-off Jump List
        // items would otherwise reappear on rebuild.
        let removed_count = removed.GetCount()?;
        let mut removed_ids: Vec<String> = Vec::new();
        for i in 0..removed_count {
            if let Ok(link) = removed.GetAt::<IShellLinkW>(i) {
                let mut buf = [0u16; 1024];
                if link.GetArguments(&mut buf).is_ok() {
                    // Slice to the first NUL terminator (the OS
                    // writes a NUL-terminated UTF-16 string; the
                    // tail is uninitialized).
                    let len = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
                    let arg = String::from_utf16_lossy(&buf[..len]);
                    // Arguments are `--open-task <id>` or
                    // `--open-task "<id>"`. Strip the prefix, then
                    // peel matching surrounding quotes.
                    //
                    // route through the shared
                    // quote-stripping helper that handles nested
                    // / multi-layer quoting (cmd.exe `start` can
                    // re-wrap the arg). A pinned-off Jump List
                    // entry whose ID round-tripped through such
                    // a shell would otherwise carry surrounding
                    // quotes back here, fail the in-set lookup
                    // against `candidates`, and reappear on the
                    // next rebuild.
                    if let Some(id) = arg.strip_prefix("--open-task ") {
                        let id = crate::plugins::strip_open_task_quotes(id);
                        if !id.is_empty() {
                            removed_ids.push(id.to_string());
                        }
                    } else if let Some(id) = arg.strip_prefix("--open-task=") {
                        let id = crate::plugins::strip_open_task_quotes(id);
                        if !id.is_empty() {
                            removed_ids.push(id.to_string());
                        }
                    }
                }
            }
        }

        // Build the collection of shell link items.
        let collection: IObjectCollection =
            CoCreateInstance(&EnumerableObjectCollection, None, CLSCTX_INPROC_SERVER)?;

        // Surface a `current_exe()` failure as a typed
        // `windows::core::Error` so the outer `rebuild_jump_list`
        // skips the rebuild entirely (better than committing a
        // broken list); the breaker logic above then keeps further
        // attempts suppressed until the next user-triggered rebuild.
        // `unwrap_or_default()` would leave `exe_path` as the empty
        // `PathBuf`, and every committed shell link would point at
        // "" — clicking a Jump List entry would produce an "Item
        // not found" dialog with no actionable path.
        let exe_path = std::env::current_exe().map_err(|e| {
            windows::core::Error::new(
                windows::core::HRESULT(-1),
                format!("current_exe() failed; cannot pin a working Jump List shortcut: {e}"),
            )
        })?;
        let exe_hstring = HSTRING::from(exe_path.to_string_lossy().as_ref());

        // `candidates` arrives pre-sorted by due-date-then-title and
        // capped at `TOP_SNAPSHOT_BUFFER`. Filter
        // user-pinned-off entries and truncate to the OS-reported
        // slot budget. The buffer is 2× `MAX_JUMP_LIST_ITEMS`, so
        // we always have enough to fill the Jump List even if
        // several of the top candidates were pinned off.
        let sorted_tasks: Vec<&TaskRow> = candidates
            .iter()
            .filter(|t| !removed_ids.contains(&t.id))
            .take(max_slots.min(MAX_JUMP_LIST_ITEMS as u32) as usize)
            .collect();

        for task in &sorted_tasks {
            let link: IShellLinkW = CoCreateInstance(&ShellLink, None, CLSCTX_INPROC_SERVER)?;

            link.SetPath(&exe_hstring)?;

            // Quote the task ID to handle IDs with spaces or special chars
            let args = HSTRING::from(format!("--open-task \"{}\"", task.id));
            link.SetArguments(&args)?;

            // Build a human-readable description.
            let mut desc_parts: Vec<String> = vec![task.title.clone()];
            if let Some(ref list) = task.list_name {
                desc_parts.push(format!("List: {list}"));
            }
            if let Some(ref due) = task.due_date {
                desc_parts.push(format!("Due: {due}"));
            }
            let description = HSTRING::from(desc_parts.join(" | "));
            link.SetDescription(&description)?;

            collection.AddObject(&link)?;
        }

        let category = HSTRING::from("Recent Tasks");
        dest_list.AppendCategory(&category, &collection)?;
        dest_list.CommitList()?;
    }

    // success-path diagnostic dropped — packaged
    // builds have no stderr surface so the line was invisible
    // anyway, and the only useful signal is the failure case
    // captured by `super::super::log_spotlight_error` upstream.
    let _ = candidates.len();
    Ok(())
}
