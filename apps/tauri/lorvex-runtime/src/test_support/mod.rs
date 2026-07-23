use std::sync::{Mutex, OnceLock};

struct EnvVarGuard {
    previous: Option<String>,
}

impl Drop for EnvVarGuard {
    fn drop(&mut self) {
        // Safety: callers hold the shared DB_PATH mutex for the
        // full guard scope; cooperating tests cannot concurrently
        // mutate the process environment through this helper.
        unsafe {
            match self.previous.as_deref() {
                Some(value) => std::env::set_var("DB_PATH", value),
                None => std::env::remove_var("DB_PATH"),
            }
        }
    }
}

/// Run `body` while `DB_PATH` is temporarily set to `value`.
///
/// This is test support only. It serializes all cooperative `DB_PATH`
/// mutations through one process-wide lock, snapshots the previous
/// value, restores it on panic, and recovers poisoned locks loudly so
/// one failing test cannot wedge the rest of a suite.
pub fn with_db_path_env_for_test<R>(value: Option<&str>, body: impl FnOnce() -> R) -> R {
    with_db_path_env_for_test_impl(value, || {}, body, |_| {})
}

fn with_db_path_env_for_test_impl<R>(
    value: Option<&str>,
    before_snapshot: impl FnOnce(),
    body: impl FnOnce() -> R,
    after_restore: impl FnOnce(Option<&str>),
) -> R {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    let mutex = LOCK.get_or_init(|| Mutex::new(()));
    let _guard = mutex.lock().unwrap_or_else(|poisoned| {
        eprintln!(
            "[lorvex] with_db_path_env_for_test: lock was poisoned by an earlier \
             panicking caller; recovering via into_inner so subsequent tests \
             observe the mutex as available. Investigate the prior panic — \
             poison-recovery is a safety net, not a normal-path event."
        );
        poisoned.into_inner()
    });

    before_snapshot();
    let previous = std::env::var("DB_PATH").ok();
    let restore_guard = EnvVarGuard {
        previous: previous.clone(),
    };

    // Safety: held under the shared DB_PATH mutex above.
    unsafe {
        match value {
            Some(value) => std::env::set_var("DB_PATH", value),
            None => std::env::remove_var("DB_PATH"),
        }
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(body));
    drop(restore_guard);
    after_restore(previous.as_deref());
    match result {
        Ok(result) => result,
        Err(payload) => std::panic::resume_unwind(payload),
    }
}

#[cfg(test)]
mod tests;
