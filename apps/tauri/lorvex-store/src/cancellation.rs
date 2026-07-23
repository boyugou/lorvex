/// Cooperative cancellation hook for long-running store operations.
///
/// The store crate must stay independent from Tauri/runtime globals, so
/// callers provide a tiny token that answers whether cancellation has
/// been requested. Long-running import/export loops call this between
/// rows, ZIP entries, blob copies, and SQL apply batches.
pub trait CancellationToken {
    fn is_cancelled(&self) -> bool;
}

#[derive(Debug, Default, Clone, Copy)]
pub struct NeverCancelled;

impl CancellationToken for NeverCancelled {
    fn is_cancelled(&self) -> bool {
        false
    }
}

pub(crate) fn check_export_cancelled(
    cancellation: &dyn CancellationToken,
) -> Result<(), crate::export::ExportError> {
    if cancellation.is_cancelled() {
        Err(crate::export::ExportError::Cancelled)
    } else {
        Ok(())
    }
}

pub(crate) fn check_import_cancelled(
    cancellation: &dyn CancellationToken,
) -> Result<(), crate::import::ImportError> {
    if cancellation.is_cancelled() {
        Err(crate::import::ImportError::Cancelled)
    } else {
        Ok(())
    }
}
