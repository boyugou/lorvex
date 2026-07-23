use std::future::Future;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};
use std::time::Duration;

use tokio::sync::Notify;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ShutdownTrigger {
    ParentProcessChanged,
    ServiceCompleted,
    Signal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ShutdownDrainOutcome {
    Drained,
    TimedOut,
}

pub(crate) const SERVICE_SHUTDOWN_DRAIN_GRACE_SECS: u64 = 10;

#[derive(Debug, Clone, Default)]
pub(crate) struct InFlightTracker {
    state: Arc<InFlightState>,
}

#[derive(Debug, Default)]
struct InFlightState {
    active: AtomicUsize,
    idle: Notify,
}

#[derive(Debug)]
pub(crate) struct InFlightGuard {
    state: Arc<InFlightState>,
}

impl InFlightTracker {
    pub(crate) fn enter(&self) -> InFlightGuard {
        self.state.active.fetch_add(1, Ordering::SeqCst);
        InFlightGuard {
            state: Arc::clone(&self.state),
        }
    }

    pub(crate) async fn wait_for_idle(self) {
        loop {
            let notified = self.state.idle.notified();
            if self.state.active.load(Ordering::SeqCst) == 0 {
                return;
            }
            notified.await;
        }
    }

    #[cfg(test)]
    pub(crate) fn active_count(&self) -> usize {
        self.state.active.load(Ordering::SeqCst)
    }
}

impl Drop for InFlightGuard {
    fn drop(&mut self) {
        let previous = self.state.active.fetch_sub(1, Ordering::SeqCst);
        if previous == 1 {
            self.state.idle.notify_waiters();
        }
    }
}

#[cfg(unix)]
pub(crate) const fn parent_process_changed(
    original_ppid: libc::pid_t,
    current_ppid: libc::pid_t,
) -> bool {
    current_ppid != original_ppid
}

pub(crate) async fn cancel_and_drain_service<F, T, E>(
    trigger: ShutdownTrigger,
    cancel_service: impl FnOnce(),
    service_waiting: F,
    application_work_idle: impl Future<Output = ()>,
    grace: Duration,
) -> Result<ShutdownDrainOutcome, E>
where
    F: Future<Output = Result<T, E>>,
{
    tracing::info!(
        ?trigger,
        grace_ms = grace.as_millis(),
        "MCP shutdown requested; cancelling service"
    );
    cancel_service();

    let service_result = if let Ok(result) = tokio::time::timeout(grace, service_waiting).await {
        result.map(|_| ())
    } else {
        tracing::error!(
            ?trigger,
            grace_ms = grace.as_millis(),
            "MCP service did not stop before shutdown grace elapsed"
        );
        return Ok(ShutdownDrainOutcome::TimedOut);
    };

    let drain_outcome = drain_application_work(trigger, application_work_idle, grace).await;
    if drain_outcome == ShutdownDrainOutcome::TimedOut {
        return Ok(ShutdownDrainOutcome::TimedOut);
    }
    service_result?;
    Ok(drain_outcome)
}

pub(crate) async fn drain_application_work(
    trigger: ShutdownTrigger,
    application_work_idle: impl Future<Output = ()>,
    grace: Duration,
) -> ShutdownDrainOutcome {
    if let Ok(()) = tokio::time::timeout(grace, application_work_idle).await {
        tracing::info!(
            ?trigger,
            "Lorvex in-flight work drained after MCP service shutdown"
        );
        ShutdownDrainOutcome::Drained
    } else {
        tracing::error!(
            ?trigger,
            grace_ms = grace.as_millis(),
            "Lorvex in-flight work did not drain before shutdown grace elapsed"
        );
        ShutdownDrainOutcome::TimedOut
    }
}

pub(crate) fn force_exit_after_drain_timeout(trigger: ShutdownTrigger) -> ! {
    tracing::error!(
        ?trigger,
        grace_secs = SERVICE_SHUTDOWN_DRAIN_GRACE_SECS,
        "MCP shutdown drain timed out; forcing process exit"
    );
    std::process::exit(0);
}

#[cfg(test)]
mod tests;
