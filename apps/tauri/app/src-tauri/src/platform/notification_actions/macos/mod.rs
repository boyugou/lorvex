//! macOS notification action implementation.
//!
//! Owns the `UNNotificationCategory` registration, the
//! `UNUserNotificationCenterDelegate` install path, and the Obj-C
//! delegate class definition. See the parent module's file-level doc
//! comment for the cross-platform rationale.
//!
//! #3303 P2 split — the previous 519-LOC `macos.rs` packed three
//! independent concerns into one file: the category-registration +
//! delegate-install entry points,
//! the Obj-C delegate class definition with its
//! `UNUserNotificationCenterDelegate` callbacks, and the per-action
//! handler bodies that drive the SQLite + sync-outbox writes when
//! the user taps Complete / Snooze / the default tap path. Lift each
//! into its own sibling so the Obj-C class can be reviewed
//! independently of the action handlers and the category-init code:
//!
//!   * `actions` — `handle_complete_action`, `handle_snooze_action`,
//!     `handle_open_task` per-action SQLite + outbox + Spotlight
//!     dispatch.
//!   * `delegate` — `LorvexNotificationDelegate` Obj-C class with the
//!     `willPresent` / `didReceive` callbacks, the
//!     `panic_payload_to_string` / `log_notification_panic` panic
//!     absorber, the `extract_task_id` userInfo decoder, and the
//!     `set_app_handle` / `get_app_handle` `OnceLock` accessors that
//!     bridge the OS callback queue to the Tauri runtime.
//!   * `mod.rs` (this file) — `register_notification_categories`,
//!     `install_notification_delegate`, and the `delegate_app_handle`
//!     accessor consumed by the parent module's typed-event error sink.

mod actions;
mod delegate;

use crate::platform::notification_strings::{action_title, NotificationActionString};

pub(super) fn register_notification_categories(locale: &str) {
    use objc2_foundation::{NSArray, NSSet, NSString};
    use objc2_user_notifications::{
        UNNotificationAction, UNNotificationActionOptions, UNNotificationCategory,
        UNNotificationCategoryOptions, UNUserNotificationCenter,
    };

    let complete_title = action_title(locale, NotificationActionString::Complete);
    let snooze_title = action_title(locale, NotificationActionString::Snooze);

    let complete_action = UNNotificationAction::actionWithIdentifier_title_options(
        &NSString::from_str("complete"),
        &NSString::from_str(complete_title),
        UNNotificationActionOptions::empty(),
    );

    let snooze_action = UNNotificationAction::actionWithIdentifier_title_options(
        &NSString::from_str("snooze"),
        &NSString::from_str(snooze_title),
        UNNotificationActionOptions::empty(),
    );

    let actions = NSArray::from_retained_slice(&[complete_action, snooze_action]);
    let intent_identifiers: objc2::rc::Retained<NSArray<NSString>> =
        NSArray::from_retained_slice(&[]);

    // Keep hidden-preview title/subtitle visible so the reminder is still
    // identifiable when macOS hides notification body text. `CustomDismissAction`
    // is harmless on macOS and keeps delegate behavior explicit for dismissals.
    // `AllowAnnouncement` is intentionally NOT set because Apple deprecated it.
    let category_options = UNNotificationCategoryOptions::HiddenPreviewsShowTitle
        | UNNotificationCategoryOptions::HiddenPreviewsShowSubtitle
        | UNNotificationCategoryOptions::CustomDismissAction;

    let category = UNNotificationCategory::categoryWithIdentifier_actions_intentIdentifiers_options(
        &NSString::from_str("task-reminder"),
        &actions,
        &intent_identifiers,
        category_options,
    );

    let categories = NSSet::from_retained_slice(&[category]);
    let center = UNUserNotificationCenter::currentNotificationCenter();
    center.setNotificationCategories(&categories);
}

pub(super) fn install_notification_delegate(app_handle: tauri::AppHandle) {
    use delegate::NotificationDelegate;
    use objc2::runtime::ProtocolObject;
    use objc2_user_notifications::{UNUserNotificationCenter, UNUserNotificationCenterDelegate};

    let delegate = NotificationDelegate::new(app_handle);
    let proto: &ProtocolObject<dyn UNUserNotificationCenterDelegate> =
        ProtocolObject::from_ref(&*delegate);

    let center = UNUserNotificationCenter::currentNotificationCenter();
    center.setDelegate(Some(proto));

    // SAFETY: Intentional leak. The delegate must live for the entire app lifetime
    // because UNUserNotificationCenter only holds a weak reference to its delegate.
    // If the Retained<NotificationDelegate> were dropped, the weak reference would
    // dangle and notification callbacks would crash. Leaking is acceptable here:
    // the object is singleton, allocated once at startup, needs no cleanup, and the
    // OS reclaims all process memory on exit.
    std::mem::forget(delegate);
}

/// Expose the delegate's stored app handle to the parent module's error
/// sink so it can emit a typed event even when the durable log path is
/// unreachable. The handle is set during delegate install; if it has
/// not been set yet (early-startup failure) the emit is skipped.
pub(super) fn delegate_app_handle() -> Option<&'static tauri::AppHandle> {
    delegate::DELEGATE_APP_HANDLE_FOR_ERRORS.get()
}
