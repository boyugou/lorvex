"""Shared Apple-only release strategy contract."""

from __future__ import annotations


APPLE_RELEASE_STRATEGY = {
    "platform_scope": "apple-only",
    "primary_platforms": [
        "macOS",
        "iOS",
        "iPadOS",
        "visionOS",
        "watchOS",
        "WidgetKit",
        "AppIntents",
    ],
    "excluded_platforms": ["Windows", "Linux"],
    "cli_product": False,
    "mcp_host": "swift-native",
    "mcp_sdk": "modelcontextprotocol/swift-sdk",
    "rust_usage": "none-at-runtime",
    "theme_system": "system-appearance",
}

SYSTEM_INTENTS_PRODUCT = "LorvexSystemIntents"
# The flagship AppShortcuts registered by `LorvexShortcutsProvider`, in
# declaration order. The system only surfaces roughly ten of an app's shortcuts,
# so this is a curated set of the highest-value entry points — not the full list
# of invokable App Intents (those keep their struct files and stay runnable from
# the Shortcuts app, Siri, and automations; they simply are not auto-registered
# shortcut phrases). `verify_system_entrypoints.py` enforces that this list and
# the provider's `AppShortcut` declarations stay in lockstep.
SYSTEM_INTENTS_ACTIONS = [
    "capture_task",
    "open_lorvex",
    "read_overview",
    "complete_task",
    "defer_task",
    "focus_task",
    "list_tasks",
    "search_tasks",
    "create_habit",
    "read_weekly_review",
]
SYSTEM_INTENTS_CAPABILITIES = {
    "shortcuts": SYSTEM_INTENTS_ACTIONS,
    "focus_filter_intent": "LorvexFocusFilterIntent",
}

CLOUDKIT_SYNC_READINESS = {
    "ready": [
        "outbound_record_export",
        "private_database_subscription",
        "remote_change_refresh",
        "inbound_record_application",
        "change_token_checkpointing",
    ],
    "pending": [],
}

CLOUDKIT_PRODUCTION_RELEASE_READINESS = {
    "ready": [
        "mas_cloudkit_entitlement_template",
        "mas_entitlement_verifier",
    ],
    "pending": [
        "cloudkit_production_schema_promotion",
        "app_store_connect_provisioning",
    ],
}


def system_intents_platform_metadata(root) -> dict[str, object]:
    return {
        "swiftpm_product": SYSTEM_INTENTS_PRODUCT,
        "source_path": str(root / "Sources" / "LorvexSystemIntents"),
        "ios_target": "LorvexSystemIntents",
        "ios_bundle_id": "com.lorvex.apple.systemintents",
        "visionos_target": "LorvexSystemIntentsVision",
        "visionos_bundle_id": "com.lorvex.apple.vision.systemintents",
        "actions": SYSTEM_INTENTS_ACTIONS,
        "capabilities": SYSTEM_INTENTS_CAPABILITIES,
    }
