//! `LorvexNotificationDelegate` Obj-C class definition + the
//! per-action dispatch body. The class implements two
//! `UNUserNotificationCenterDelegate` callbacks:
//!
//! * `willPresentNotification` — chooses which presentation
//!   options macOS should use when the notification fires while
//!   the app is in the foreground.
//! * `didReceiveNotificationResponse` — fires when the user
//!   taps an action (Complete / Snooze) or the default tap path.
//!   Routes through the typed
//!   `super::super::NotificationAction::parse` so the dispatch is
//!   exhaustive.
//!
//! Both callbacks wrap their bodies in
//! `bootstrap::catch_unwind_without_default_panic_hook` because a
//! panic crossing the Obj-C → Rust runtime boundary is UB on macOS,
//! and the macOS notification system stops delivering subsequent
//! callbacks for the rest of the process when one of them aborts.

use objc2::rc::Retained;
use objc2::runtime::AnyObject;
use objc2::{define_class, msg_send, AllocAnyThread};
use objc2_foundation::{NSObject, NSObjectProtocol, NSString};
use objc2_user_notifications::{
    UNNotification, UNNotificationPresentationOptions, UNNotificationResponse,
    UNUserNotificationCenter, UNUserNotificationCenterDelegate,
};
use std::sync::OnceLock;
use tauri::AppHandle;

use super::actions::{handle_complete_action, handle_open_task, handle_snooze_action};

/// Global storage for the AppHandle, set once during delegate installation.
/// The delegate itself cannot hold non-trivially-constructed Rust state in
/// its ivars (ObjC class layout constraints), so we use a static.
static DELEGATE_APP_HANDLE: OnceLock<AppHandle> = OnceLock::new();

/// Separate accessor so `record_notification_action_error` in the
/// parent module can emit the typed Tauri event when the durable
/// error_logs write fails. Same OnceLock semantics — set exactly
/// once during delegate install. Without it, a pool-failure on the
/// dispatch side would drop the action with zero user-facing trace.
pub(super) static DELEGATE_APP_HANDLE_FOR_ERRORS: OnceLock<AppHandle> = OnceLock::new();

pub(super) fn set_app_handle(handle: AppHandle) {
    // Emit a structured warn-log on the duplicate-call path so a
    // future hot-reload refactor re-entering this path is
    // observable in Settings → Diagnostics on packaged builds
    // instead of silently dropping the new handle. The `set` call
    // itself still keeps the first handle by design — later writes
    // from Tauri's runtime would dangle if we swapped mid-flight.
    // A bare `OnceLock::set` plus `debug_assert!` would lose the
    // signal on release builds (no console on macOS, no error_logs
    // entry).
    // Mirror to the error-sink accessor so the parent module can
    // emit typed events on dispatch failure.
    let _ = DELEGATE_APP_HANDLE_FOR_ERRORS.set(handle.clone());
    if DELEGATE_APP_HANDLE.set(handle).is_err() {
        if let Ok(conn) = crate::db::get_conn() {
            let _ = crate::commands::diagnostics::append_error_log_internal(
                &conn,
                "platform.notification_actions",
                "set_app_handle invoked more than once; keeping the first AppHandle. \
                 This indicates a duplicate delegate-install path (hot reload, test \
                 isolation, or a missed cfg gate) — the second handle would race the \
                 first on notification dispatch.",
                None,
                Some("warn".to_string()),
            );
        }
    }
}

pub(super) fn get_app_handle() -> Option<&'static AppHandle> {
    DELEGATE_APP_HANDLE.get()
}

define_class! {
    #[unsafe(super(NSObject))]
    #[name = "LorvexNotificationDelegate"]
    #[thread_kind = AllocAnyThread]
    pub(super) struct NotificationDelegate;

    unsafe impl NSObjectProtocol for NotificationDelegate {}

    unsafe impl UNUserNotificationCenterDelegate for NotificationDelegate {
        #[unsafe(method(userNotificationCenter:willPresentNotification:withCompletionHandler:))]
        fn will_present_notification(
            &self,
            _center: &UNUserNotificationCenter,
            _notification: &UNNotification,
            completion_handler: &block2::DynBlock<dyn Fn(UNNotificationPresentationOptions)>,
        ) {
            // Panic safety: symmetric with the
            // sibling `did_receive_notification_response` callback
            // — any panic propagating into the Obj-C runtime is UB
            // on macOS. The body is small today but a future log
            // line or state inspection would silently regress.
            let panic_outcome = crate::bootstrap::catch_unwind_without_default_panic_hook(
                std::panic::AssertUnwindSafe(|| {
                    UNNotificationPresentationOptions::Banner
                        | UNNotificationPresentationOptions::Sound
                        | UNNotificationPresentationOptions::List
                }),
            );

            let options = match panic_outcome {
                Ok(opts) => opts,
                Err(payload) => {
                    let detail = panic_payload_to_string(&payload);
                    log_notification_panic("will_present_notification", &detail);
                    // Conservative fallback: still surface the
                    // notification with the same options so the
                    // user sees it.
                    UNNotificationPresentationOptions::Banner
                        | UNNotificationPresentationOptions::Sound
                        | UNNotificationPresentationOptions::List
                }
            };

            // ALWAYS fire the completion handler — macOS times out
            // and stops delivering presentation callbacks if this
            // is missed.
            completion_handler.call((options,));
        }

        #[unsafe(method(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:))]
        fn did_receive_notification_response(
            &self,
            _center: &UNUserNotificationCenter,
            response: &UNNotificationResponse,
            completion_handler: &block2::DynBlock<dyn Fn()>,
        ) {
            // Panic safety (audit): the dispatch helpers below reach
            // into the SQLite writer pool, the HLC mutex, and the
            // sync outbox. Any panic — poisoned mutex, allocation
            // failure under memory pressure, schema drift — that
            // propagates back into the Objective-C runtime is
            // undefined behavior on macOS (process abort at best).
            // The panic absorber swallows the unwind so the completion
            // handler still fires; without it, an aborted callback
            // can leave the macOS notification system refusing to
            // deliver subsequent action callbacks for the rest of
            // the app launch.
            let panic_outcome = crate::bootstrap::catch_unwind_without_default_panic_hook(
                std::panic::AssertUnwindSafe(|| {
                    let action_id = response.actionIdentifier().to_string();
                    let task_id = extract_task_id(response);

                    if let Some(task_id) = task_id {
                        // parse the FFI string into a
                        // closed `NotificationAction` enum. The
                        // dispatch is exhaustive — adding a future
                        // category like "delete" forces the
                        // compiler to demand a corresponding arm,
                        // and unknown identifiers route to the
                        // explicit `Unknown` arm with a diagnostic
                        // emit instead of being silently folded
                        // into the default-tap open path.
                        match super::super::NotificationAction::parse(&action_id) {
                            super::super::NotificationAction::Complete => {
                                handle_complete_action(&task_id);
                            }
                            super::super::NotificationAction::Snooze => {
                                handle_snooze_action(&task_id);
                            }
                            super::super::NotificationAction::Default => {
                                handle_open_task(&task_id);
                            }
                            super::super::NotificationAction::Unknown(raw) => {
                                // Surface the unknown id to error_logs so
                                // a missing dispatcher arm shows up in
                                // Settings → Diagnostics on packaged
                                // builds, then fall back to the open path
                                // (the safest interpretation of an
                                // unrecognised tap).
                                super::super::record_notification_action_error(
                                    "unknown",
                                    &task_id,
                                    &format!(
                                        "received unknown UN action identifier {raw:?}; \
                                         treating as default tap (open task)"
                                    ),
                                );
                                handle_open_task(&task_id);
                            }
                        }
                    }
                }),
            );

            if let Err(payload) = panic_outcome {
                let detail = panic_payload_to_string(&payload);
                log_notification_panic("did_receive_notification_response", &detail);
            }

            // ALWAYS fire the completion handler — even if the
            // dispatch panicked. macOS times out and stops
            // delivering callbacks if this is missed.
            completion_handler.call(());
        }
    }
}

impl NotificationDelegate {
    pub(super) fn new(app_handle: AppHandle) -> Retained<Self> {
        set_app_handle(app_handle);
        let this = Self::alloc().set_ivars(());
        unsafe { msg_send![super(this), init] }
    }
}

/// Stringify an arbitrary panic payload so the diagnostic log gets a
/// useful message regardless of what the panicking call site
/// supplied (`panic!("foo")`, `panic!("{}", err)`, structured
/// payloads). Mirrors the pattern used elsewhere in the platform
/// layer where the panic must be absorbed across an FFI boundary.
fn panic_payload_to_string(payload: &Box<dyn std::any::Any + Send>) -> String {
    if let Some(s) = payload.downcast_ref::<&'static str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "non-string panic payload".to_string()
    }
}

fn log_notification_panic(callback: &str, detail: &str) {
    let message =
        format!("[platform:notification_actions] panic in {callback} absorbed across FFI boundary");
    // Wrap the DB-write attempt in a dedicated absorber so a
    // recursive failure here can't escape. If the SQLite pool is
    // poisoned (often the same failure mode that triggered the
    // outer panic), `get_conn()` itself can panic, and that second
    // panic would propagate back through the original ObjC → Rust
    // callback's panic absorber after the logging helper aborted.
    let detail_owned = detail.to_string();
    let _ = crate::bootstrap::catch_unwind_without_default_panic_hook(
        std::panic::AssertUnwindSafe(|| {
            if let Ok(conn) = crate::db::get_conn() {
                let _ = crate::commands::diagnostics::error_logs::append_error_log_internal(
                    &conn,
                    "platform.notification_actions",
                    &message,
                    Some(detail_owned),
                    Some("error".to_string()),
                );
            }
        }),
    );
}

/// Extract the taskId from the notification's userInfo dictionary.
///
/// Surface the type-mismatch case (an `is_some()` value that is not
/// an NSString) to `error_logs` so a future Tauri-plugin upgrade
/// that switches the underlying type is observable instead of
/// silently dropping every notification action.
fn extract_task_id(response: &UNNotificationResponse) -> Option<String> {
    let notification = response.notification();
    let request = notification.request();
    let content = request.content();
    let user_info = content.userInfo();

    // The frontend sends `extra: { taskId: "..." }` which the notification
    // plugin stores in userInfo. The key is an NSString.
    let key = NSString::from_str("taskId");
    let value: Option<Retained<AnyObject>> = user_info.objectForKey(&key);
    match value {
        None => None,
        Some(obj) => {
            // Safe downcast via objc2's runtime class check (isKindOfClass:).
            if let Some(s) = obj.downcast_ref::<NSString>() {
                Some(s.to_string())
            } else {
                super::super::record_notification_action_error(
                    "extract_task_id",
                    "<unknown>",
                    "userInfo[taskId] is present but not an NSString",
                );
                None
            }
        }
    }
}
