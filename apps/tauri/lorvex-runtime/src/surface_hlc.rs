//! Shared process-local HLC runtime for Lorvex write surfaces.
//!
//! The app, CLI, and MCP server each run in their own process, so they
//! cannot share one in-memory clock. They do, however, need the same
//! lifecycle contract: derive a surface-tagged suffix from the stable
//! device id, seed past local history before first write, recover from
//! poisoned locks, observe merge/remote HLCs, and reset cleanly in
//! tests. This module owns that contract; each surface supplies only
//! its storage/error/logging adapters.

use std::convert::Infallible;
use std::ops::{Deref, DerefMut};
use std::sync::{Mutex, MutexGuard};
use std::time::{SystemTime, UNIX_EPOCH};

use lorvex_domain::hlc::{Hlc, HlcParseError, HlcSurface};
use lorvex_domain::hlc_state::HlcState;

use crate::device_id_to_hlc_suffix;

/// Process-local HLC runtime for one write surface.
#[derive(Debug)]
pub struct SurfaceHlcRuntime {
    state: Mutex<Option<SurfaceHlcState>>,
}

#[derive(Debug)]
struct SurfaceHlcState {
    device_id: String,
    surface: HlcSurface,
    state: HlcState,
}

/// Whether an initialization call created fresh state or found the
/// same surface/device already initialized.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SurfaceHlcInitOutcome {
    Initialized,
    AlreadyInitialized,
}

/// Runtime errors from the shared HLC shell. The seed callback's
/// native error type is preserved so adapters can keep their existing
/// surface-specific error policy.
#[derive(Debug)]
pub enum SurfaceHlcError<E = Infallible> {
    Seed(E),
    InvalidSuffix(HlcParseError),
    DifferentIdentity {
        existing_device_id: String,
        existing_surface: HlcSurface,
        requested_device_id: String,
        requested_surface: HlcSurface,
    },
    NotInitialized,
}

impl<E> SurfaceHlcError<E> {
    /// Convert the seed error while preserving the runtime error kind.
    pub fn map_seed<F, T>(self, f: F) -> SurfaceHlcError<T>
    where
        F: FnOnce(E) -> T,
    {
        match self {
            Self::Seed(error) => SurfaceHlcError::Seed(f(error)),
            Self::InvalidSuffix(error) => SurfaceHlcError::InvalidSuffix(error),
            Self::DifferentIdentity {
                existing_device_id,
                existing_surface,
                requested_device_id,
                requested_surface,
            } => SurfaceHlcError::DifferentIdentity {
                existing_device_id,
                existing_surface,
                requested_device_id,
                requested_surface,
            },
            Self::NotInitialized => SurfaceHlcError::NotInitialized,
        }
    }
}

impl<E: std::fmt::Display> std::fmt::Display for SurfaceHlcError<E> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Seed(error) => write!(f, "{error}"),
            Self::InvalidSuffix(error) => {
                write!(f, "HlcState::new rejected derived suffix: {error}")
            }
            Self::DifferentIdentity {
                existing_device_id,
                existing_surface,
                requested_device_id,
                requested_surface,
            } => write!(
                f,
                "HLC already initialized for {existing_surface:?}/{existing_device_id}, \
                 cannot reinitialize for {requested_surface:?}/{requested_device_id}"
            ),
            Self::NotInitialized => write!(f, "HLC not initialized"),
        }
    }
}

impl<E> std::error::Error for SurfaceHlcError<E> where
    E: std::fmt::Debug + std::fmt::Display + std::error::Error + 'static
{
}

impl SurfaceHlcRuntime {
    /// Create an empty process-local HLC runtime.
    #[must_use]
    pub const fn new() -> Self {
        Self {
            state: Mutex::new(None),
        }
    }

    /// Ensure the runtime has live HLC state for the requested
    /// device/surface, running the seed callback before publication.
    pub fn ensure_initialized<E>(
        &self,
        device_id: String,
        surface: HlcSurface,
        seed: impl FnOnce(&mut HlcState) -> Result<(), E>,
    ) -> Result<SurfaceHlcInitOutcome, SurfaceHlcError<E>> {
        let mut guard = self.lock_state();
        Self::ensure_initialized_locked(&mut guard, device_id, surface, seed)
    }

    /// Ensure initialization and return a long-scoped mutable guard to
    /// the shared HLC state. CLI and MCP use this for mutation sessions
    /// that mint many stamps under one lock acquisition.
    pub fn lock_initialized<E>(
        &self,
        device_id: String,
        surface: HlcSurface,
        seed: impl FnOnce(&mut HlcState) -> Result<(), E>,
    ) -> Result<SurfaceHlcGuard<'_>, SurfaceHlcError<E>> {
        let mut guard = self.lock_state();
        Self::ensure_initialized_locked(&mut guard, device_id, surface, seed)?;
        Ok(SurfaceHlcGuard { guard })
    }

    /// Return a long-scoped guard when the runtime is already
    /// initialized, without invoking any device-id or seed callbacks.
    pub fn lock_existing(&self) -> Result<SurfaceHlcGuard<'_>, SurfaceHlcError<Infallible>> {
        let guard = self.lock_state();
        if guard.is_none() {
            return Err(SurfaceHlcError::NotInitialized);
        }
        Ok(SurfaceHlcGuard { guard })
    }

    /// Generate and stringify the next HLC.
    pub fn generate_version(&self) -> Result<String, SurfaceHlcError<Infallible>> {
        Ok(self.generate_hlc()?.to_string())
    }

    /// Generate the next HLC.
    pub fn generate_hlc(&self) -> Result<Hlc, SurfaceHlcError<Infallible>> {
        let mut guard = self.lock_state();
        let state = guard.as_mut().ok_or(SurfaceHlcError::NotInitialized)?;
        Ok(state.state.generate())
    }

    /// Observe an already-parsed HLC if the runtime is initialized.
    /// Returns `false` when the event was skipped because no state was
    /// available yet.
    pub fn observe_hlc_if_initialized(&self, observed: &Hlc) -> bool {
        let mut guard = self.lock_state();
        let Some(state) = guard.as_mut() else {
            return false;
        };
        state.state.update_on_receive(observed, current_wall_ms());
        true
    }

    /// Parse and observe a remote HLC string. Malformed strings are
    /// reported to the supplied logger and otherwise ignored so the
    /// caller's sync/apply error path remains authoritative.
    pub fn observe_remote_version_str<L>(
        &self,
        version: &str,
        logger: L,
    ) -> Result<(), SurfaceHlcError<Infallible>>
    where
        L: FnOnce(&str, &HlcParseError),
    {
        let parsed = match Hlc::parse(version) {
            Ok(hlc) => hlc,
            Err(error) => {
                logger(version, &error);
                return Ok(());
            }
        };
        let _ = self.observe_hlc_if_initialized(&parsed);
        Ok(())
    }

    /// Return the initialized device id.
    pub fn device_id(&self) -> Result<String, SurfaceHlcError<Infallible>> {
        let guard = self.lock_state();
        guard
            .as_ref()
            .map(|state| state.device_id.clone())
            .ok_or(SurfaceHlcError::NotInitialized)
    }

    /// Return the initialized device id if present.
    #[must_use]
    pub fn try_device_id(&self) -> Option<String> {
        let guard = self.lock_state();
        guard.as_ref().map(|state| state.device_id.clone())
    }

    /// Reset process-local HLC state. Production callers should never
    /// use this; tests need it to swap temp database identities inside
    /// one test binary.
    pub fn reset_for_tests(&self) {
        let mut guard = self.lock_state();
        *guard = None;
    }

    fn ensure_initialized_locked<E>(
        guard: &mut MutexGuard<'_, Option<SurfaceHlcState>>,
        device_id: String,
        surface: HlcSurface,
        seed: impl FnOnce(&mut HlcState) -> Result<(), E>,
    ) -> Result<SurfaceHlcInitOutcome, SurfaceHlcError<E>> {
        if let Some(existing) = guard.as_ref() {
            if existing.device_id == device_id && existing.surface == surface {
                return Ok(SurfaceHlcInitOutcome::AlreadyInitialized);
            }
            return Err(SurfaceHlcError::DifferentIdentity {
                existing_device_id: existing.device_id.clone(),
                existing_surface: existing.surface,
                requested_device_id: device_id,
                requested_surface: surface,
            });
        }

        let suffix = device_id_to_hlc_suffix(&device_id, surface);
        let mut state = HlcState::new(suffix).map_err(SurfaceHlcError::InvalidSuffix)?;
        seed(&mut state).map_err(SurfaceHlcError::Seed)?;
        **guard = Some(SurfaceHlcState {
            device_id,
            surface,
            state,
        });
        Ok(SurfaceHlcInitOutcome::Initialized)
    }

    fn lock_state(&self) -> MutexGuard<'_, Option<SurfaceHlcState>> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

impl Default for SurfaceHlcRuntime {
    fn default() -> Self {
        Self::new()
    }
}

/// Long-scoped mutable guard over initialized HLC state.
pub struct SurfaceHlcGuard<'a> {
    guard: MutexGuard<'a, Option<SurfaceHlcState>>,
}

impl Deref for SurfaceHlcGuard<'_> {
    type Target = HlcState;

    fn deref(&self) -> &Self::Target {
        &self
            .guard
            .as_ref()
            .expect("SurfaceHlcGuard constructed only after initialization")
            .state
    }
}

impl DerefMut for SurfaceHlcGuard<'_> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self
            .guard
            .as_mut()
            .expect("SurfaceHlcGuard constructed only after initialization")
            .state
    }
}

fn current_wall_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
}
