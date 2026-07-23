//! Windows COM apartment lifecycle guard.
//!
//! The standard COM contract requires every successful
//! `CoInitializeEx` (i.e. `S_OK`) to be paired with a matching
//! `CoUninitialize` on the same thread before the thread exits.
//! Tauri's IPC threads are pooled, so calling
//! `CoInitializeEx(None, COINIT_APARTMENTTHREADED)` and discarding
//! the `HRESULT` from a per-feature call site (badge, spotlight,
//! ...) would leak an apartment registration on every pooled
//! thread; under sustained load the pool could exhaust
//! apartment-thread slots.
//!
//! `S_FALSE` (already initialized by someone else on this thread) and
//! `RPC_E_CHANGED_MODE` (already initialized with a different model) must
//! NOT be paired with `CoUninitialize` — those return codes signal that
//! someone else owns the lifecycle and we'd be uninitializing their
//! apartment out from under them.
//!
//! This module owns the only `CoInitializeEx` calls in the codebase; the
//! returned guard's `Drop` impl handles the asymmetric pairing rule
//! correctly.

#![cfg(target_os = "windows")]

use windows::core::HRESULT;
use windows::Win32::Foundation::{RPC_E_CHANGED_MODE, S_FALSE, S_OK};
use windows::Win32::System::Com::{CoInitializeEx, CoUninitialize, COINIT_APARTMENTTHREADED};

/// Owned/borrowed state for a thread's COM apartment.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ApartmentOwnership {
    /// `CoInitializeEx` returned `S_OK` — we initialised the apartment
    /// and are responsible for the matching `CoUninitialize`.
    Owned,
    /// `CoInitializeEx` returned `S_FALSE` — the thread was already
    /// initialised with the same model. Someone else owns the lifecycle;
    /// we must NOT uninitialize.
    BorrowedSameModel,
    /// `CoInitializeEx` returned `RPC_E_CHANGED_MODE` — the thread is
    /// already initialised with a different model. Same lifecycle rule
    /// as `BorrowedSameModel`: we don't own anything to release.
    BorrowedDifferentModel,
}

/// Pure classification of a `CoInitializeEx` HRESULT into our
/// ownership taxonomy. Extracted so the windows-gated unit tests can
/// pin the mapping without touching the COM runtime.
fn classify_apartment_ownership(hresult: HRESULT) -> ApartmentOwnership {
    if hresult == S_OK {
        ApartmentOwnership::Owned
    } else if hresult == S_FALSE {
        ApartmentOwnership::BorrowedSameModel
    } else if hresult == RPC_E_CHANGED_MODE {
        ApartmentOwnership::BorrowedDifferentModel
    } else {
        // Any other HRESULT from CoInitializeEx is unexpected
        // (E_OUTOFMEMORY, E_INVALIDARG). Treat as borrowed so we
        // don't double-uninitialize on top of whatever did succeed.
        // The caller will fail at the next COM call with a clearer
        // error.
        ApartmentOwnership::BorrowedDifferentModel
    }
}

/// RAII guard that initialises an STA COM apartment and uninitialises
/// it on drop *only* when we own the lifecycle.
///
/// Hold the guard across every COM call you make on the thread; let it
/// drop after the last call so the matching `CoUninitialize` lands.
pub struct ComApartmentGuard {
    ownership: ApartmentOwnership,
    /// Stash the original HRESULT so the (rare) caller that wants to
    /// surface "different model" to a log can read it without
    /// re-checking.
    initial_hresult: HRESULT,
}

impl ComApartmentGuard {
    /// Initialise the calling thread's STA apartment. Always returns a
    /// guard, even when `CoInitializeEx` reported a "borrowed" state —
    /// the guard's Drop logic then becomes a no-op.
    ///
    /// # Safety
    ///
    /// Calling COM functions from a thread without a live apartment is
    /// undefined behavior; this constructor exists to make the lifetime
    /// explicit. The caller must keep the guard alive until the last
    /// COM call on the thread completes.
    pub fn enter_sta() -> Self {
        // SAFETY: `CoInitializeEx` is the canonical entry to set up
        // a COM apartment. Calling it from a non-COM-aware thread is
        // safe; calling it more than once on the same thread returns
        // `S_FALSE` / `RPC_E_CHANGED_MODE` rather than failing — the
        // ownership tracking below routes those to a no-op Drop.
        let hresult = unsafe { CoInitializeEx(None, COINIT_APARTMENTTHREADED) };
        let ownership = classify_apartment_ownership(hresult);
        Self {
            ownership,
            initial_hresult: hresult,
        }
    }

    /// `true` if we own the apartment lifecycle (i.e. `CoInitializeEx`
    /// returned `S_OK`). Test-only inspector — production callers rely
    /// on the RAII `Drop` impl to do the right thing.
    #[cfg(test)]
    pub fn is_owned(&self) -> bool {
        self.ownership == ApartmentOwnership::Owned
    }

    /// `true` when this thread is now operating in an STA — either
    /// because we initialised it (`Owned`) or because someone else
    /// initialised it as STA before us (`BorrowedSameModel`).
    ///
    /// STA-affined COM interfaces (`ITaskbarList3`,
    /// `ICustomDestinationList`, the shell's CustomDestinationList
    /// helpers) require an STA. Use this helper to gate STA-only
    /// code paths. The `BorrowedDifferentModel` case
    /// (`RPC_E_CHANGED_MODE` from `CoInitializeEx`) on a thread
    /// already living in an MTA produces non-deterministic behavior
    /// — the shell's `IShellLinkW` cocreate may still succeed via the
    /// agile proxy fast-path and then crash inside `BeginList`.
    pub fn is_in_sta(&self) -> bool {
        matches!(
            self.ownership,
            ApartmentOwnership::Owned | ApartmentOwnership::BorrowedSameModel
        )
    }

    /// The original HRESULT from `CoInitializeEx`. Test-only diagnostic
    /// — production callers don't read this back.
    #[cfg(test)]
    pub fn initial_hresult(&self) -> HRESULT {
        self.initial_hresult
    }
}

impl Drop for ComApartmentGuard {
    fn drop(&mut self) {
        if self.ownership == ApartmentOwnership::Owned {
            // SAFETY: we own the apartment lifecycle (CoInitializeEx
            // returned S_OK). Pairing CoUninitialize with that S_OK on
            // the same thread is required by the COM contract. The
            // borrowed cases skip this so we don't release someone
            // else's registration.
            unsafe { CoUninitialize() };
        }
    }
}

#[cfg(test)]
mod tests;
