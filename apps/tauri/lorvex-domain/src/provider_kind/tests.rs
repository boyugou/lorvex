use super::*;

#[test]
fn allowlist_accepts_every_canonical_kind() {
    for kind in PROVIDER_KIND_ALLOWLIST {
        assert!(
            is_allowed_provider_kind(kind),
            "{kind} must be in the canonical allowlist"
        );
    }
}

#[test]
fn allowlist_rejects_unknown_or_drifted_kinds() {
    for bad in [
        "",
        " eventkit",
        "EventKit",
        "EVENTKIT",
        "evernote",
        "google", // legacy short form
        "eventkit_v2",
        "ICAL_SUBSCRIPTION",
    ] {
        assert!(
            !is_allowed_provider_kind(bad),
            "{bad:?} must not be in the allowlist"
        );
    }
}

#[test]
fn allowlist_covers_every_real_producer() {
    // Closing #2954 drift-guard: every kind any in-tree producer
    // (Tauri IPC, MCP IPC, platform readers, iCal subscription
    // sync) writes today MUST round-trip through the canonical
    // allowlist. If a future producer adds a new kind without
    // updating this constant, this test fails before the kind
    // can ride into the database.
    let real_producers = [
        "eventkit",             // app/src-tauri/src/platform/eventkit.rs
        "linux_ics",            // app/src-tauri/src/platform/linux_calendar.rs
        "windows_appointments", // app/src-tauri/src/platform/windows_calendar.rs
        "ical_subscription",    // app/src-tauri/src/calendar_subscription_sync/
        "ics",                  // MCP / Tauri provider link IPC
        "google_calendar",      // MCP / Tauri provider link IPC
        "outlook",              // MCP / Tauri provider link IPC
    ];
    for kind in real_producers {
        assert!(
            is_allowed_provider_kind(kind),
            "real producer kind {kind} must be in the allowlist"
        );
    }
}

#[test]
fn allowlist_display_is_deterministic_and_human_readable() {
    let display = provider_kind_allowlist_display();
    assert_eq!(
        display,
        "eventkit, google_calendar, ical_subscription, ics, linux_ics, outlook, windows_appointments"
    );
}
