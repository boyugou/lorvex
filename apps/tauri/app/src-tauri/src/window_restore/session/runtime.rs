use super::super::restore::restore_main_window_once;
#[cfg(target_os = "macos")]
use super::super::restore::{
    append_window_restore_log, append_window_restore_trace, capture_window_restore_snapshot,
    hard_recover_main_window,
};
#[cfg(target_os = "macos")]
use super::state::{
    claim_window_restore_in_flight, mark_window_restore_pending, release_window_restore_in_flight,
    take_window_restore_pending,
};
#[cfg(target_os = "macos")]
use lorvex_domain::new_entity_id_string;
#[cfg(target_os = "macos")]
use std::{sync::mpsc, time::Duration};
use tauri::AppHandle;
#[cfg(target_os = "macos")]
use tauri::Manager;

fn focus_window(app: &AppHandle, trigger: &'static str) {
    #[cfg(target_os = "macos")]
    {
        if !claim_window_restore_in_flight() {
            mark_window_restore_pending();
            append_window_restore_trace(
                "Window restore request skipped because another restore session is active",
                || {
                    Some(format!(
                        "trigger={trigger} stage=session_skip reason=in_flight pending=true snapshot={}",
                        capture_window_restore_snapshot(app)
                    ))
                },
            );
            return;
        }

        let app_handle = app.clone();
        let session_id = new_entity_id_string();
        std::thread::spawn(move || {
            {
                struct RestoreInFlightGuard;
                impl Drop for RestoreInFlightGuard {
                    fn drop(&mut self) {
                        release_window_restore_in_flight();
                    }
                }
                let _guard = RestoreInFlightGuard;

                append_window_restore_trace("Window restore session started", || {
                    Some(format!(
                        "session_id={session_id} trigger={trigger} stage=session_start snapshot={}",
                        capture_window_restore_snapshot(&app_handle)
                    ))
                });

                // this flag never actually crosses a
                // thread boundary — every read and store happens on
                // this worker thread. The main-thread callback at
                // line 82 only returns its result through the mpsc
                // channel; the store at line 124 below runs on the
                // worker after `attempt_rx.recv_timeout` returns.
                // Dropping the Arc<AtomicBool> + Ordering::Relaxed
                // apparatus removes the false cross-thread-sync
                // implication and makes the actual single-threaded
                // invariant visible at a glance.
                let mut restored_flag = false;
                for (attempt_index, delay_ms) in [0_u64, 120, 260, 520].iter().enumerate() {
                    if restored_flag {
                        break;
                    }
                    let attempt = attempt_index + 1;
                    if *delay_ms > 0 {
                        std::thread::sleep(Duration::from_millis(*delay_ms));
                    }
                    append_window_restore_trace("Window restore attempt dispatching", || {
                        Some(format!(
                            "session_id={session_id} trigger={trigger} stage=attempt_dispatch attempt={attempt} delay_ms={} snapshot={}",
                            delay_ms,
                            capture_window_restore_snapshot(&app_handle)
                        ))
                    });
                    let app_for_call = app_handle.clone();
                    let (attempt_tx, attempt_rx) = mpsc::sync_channel::<bool>(1);
                    if let Err(error) = app_handle.run_on_main_thread(move || {
                        let restored = restore_main_window_once(&app_for_call);
                        let _ = attempt_tx.send(restored);
                    }) {
                        append_window_restore_log(
                            "warn",
                            "Replay attempt failed to dispatch on main thread",
                            Some(format!(
                                "session_id={session_id} trigger={trigger} stage=replay_dispatch attempt={attempt} error={error}"
                            )),
                        );
                        continue;
                    }

                    let attempt_restored = match attempt_rx.recv_timeout(Duration::from_millis(800))
                    {
                        Ok(restored) => restored,
                        Err(mpsc::RecvTimeoutError::Timeout) => {
                            append_window_restore_log(
                                "warn",
                                "Restore attempt timed out waiting for main-thread completion",
                                Some(format!(
                                    "session_id={session_id} trigger={trigger} stage=attempt_timeout attempt={attempt} timeout_ms=800"
                                )),
                            );
                            false
                        }
                        Err(mpsc::RecvTimeoutError::Disconnected) => {
                            append_window_restore_log(
                                "warn",
                                "Restore attempt completion channel disconnected",
                                Some(format!(
                                    "session_id={session_id} trigger={trigger} stage=attempt_disconnected attempt={attempt}"
                                )),
                            );
                            false
                        }
                    };

                    if attempt_restored {
                        restored_flag = true;
                    }
                    append_window_restore_trace("Window restore attempt completed", || {
                        Some(format!(
                            "session_id={session_id} trigger={trigger} stage=attempt_complete attempt={attempt} restored={} snapshot={}",
                            restored_flag,
                            capture_window_restore_snapshot(&app_handle)
                        ))
                    });
                }

                if !restored_flag {
                    let app_for_final = app_handle.clone();
                    if let Err(error) = app_handle.run_on_main_thread(move || {
                        hard_recover_main_window(&app_for_final);
                    }) {
                        append_window_restore_log(
                            "error",
                            "Hard-recover failed to dispatch on main thread",
                            Some(format!(
                                "session_id={session_id} trigger={trigger} stage=hard_recover_dispatch error={error}"
                            )),
                        );
                    } else {
                        let mut last_state = (false, true, false);
                        let mut settled = false;
                        let verification_label = "main";
                        // after each sleep, check the wall-
                        // clock elapsed. If it's more than 2× the
                        // requested duration, the process almost
                        // certainly slept through a macOS system-sleep
                        // (NSWorkspaceWillSleepNotification doesn't
                        // interrupt std::thread::sleep — it resumes
                        // immediately on wake). The intermediate
                        // window state is probably meaningless because
                        // AppKit is still repainting; skip the
                        // settled-check for this iteration so a
                        // short-circuit doesn't freeze on a stale
                        // just-woke-up snapshot. The next loop
                        // iteration (up to `verify_delay=520`)
                        // re-probes after a real wall-clock delay.
                        for verify_delay in [120_u64, 260, 520] {
                            let before_sleep = std::time::Instant::now();
                            std::thread::sleep(Duration::from_millis(verify_delay));
                            let elapsed = before_sleep.elapsed();
                            let slept_through_system_sleep =
                                elapsed > Duration::from_millis(verify_delay * 2);
                            last_state = if let Some(window) =
                                app_handle.get_webview_window(verification_label)
                            {
                                (
                                    window.is_visible().unwrap_or(false),
                                    window.is_minimized().unwrap_or(false),
                                    window.is_focused().unwrap_or(false),
                                )
                            } else {
                                (false, true, false)
                            };
                            if slept_through_system_sleep {
                                append_window_restore_log(
                                    "warn",
                                    "System sleep detected during hard-recover verify; re-probing",
                                    Some(format!(
                                        "session_id={session_id} trigger={trigger} stage=verify_system_sleep \
                                         requested_ms={verify_delay} actual_ms={}",
                                        elapsed.as_millis()
                                    )),
                                );
                                continue;
                            }
                            if last_state.0 && !last_state.1 && last_state.2 {
                                settled = true;
                                break;
                            }
                        }
                        if !settled {
                            let (is_visible, is_minimized, is_focused) = last_state;
                            append_window_restore_log(
                                "warn",
                                "Window restore escalated to hard recover and remains incomplete",
                                Some(format!(
                                    "session_id={session_id} trigger={trigger} stage=hard_recover target={verification_label} visible={is_visible} minimized={is_minimized} focused={is_focused}"
                                )),
                            );
                        }
                    }
                }

                append_window_restore_trace("Window restore session finished", || {
                    Some(format!(
                        "session_id={session_id} trigger={trigger} stage=session_end restored={} snapshot={}",
                        restored_flag,
                        capture_window_restore_snapshot(&app_handle)
                    ))
                });
            }
            let replay_after_drop = take_window_restore_pending();

            if replay_after_drop {
                focus_window(&app_handle, "pending_replay");
            }
        });
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = trigger;
        let _ = restore_main_window_once(app);
    }
}

pub(crate) fn focus_main_window(app: &AppHandle, trigger: &'static str) {
    focus_window(app, trigger);
}

pub(crate) fn focus_primary_window(app: &AppHandle, trigger: &'static str) {
    focus_window(app, trigger);
}
