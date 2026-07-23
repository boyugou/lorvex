# Local Preference Registry Audit

Source type: Lorvex source audit; no external webpage

Last verified: 2026-07-10 against code snapshot `cd2b10f0e`

## Contract Shape

`PreferenceKeys.allKnownPreferenceKeys` is not just documentation. It is the
write allowlist used by system/App Intent and MCP preference surfaces. A key in
the list can be stored as arbitrary canonical JSON, exported, and — unless it
is in `localOnlyPreferenceKeys` — synchronized as a CloudKit `preference`
entity.

Tests also enumerate the registry, turning the set into an intentional
compatibility contract.

## Registry-Only Keys

The registry defines 38 `pref*` keys. The following 26 have no reference in
shipping Swift source outside `PreferenceKeys.swift` itself (neither through
their constant nor their literal value):

- `weekly_review_day`
- `dashboard_layout`
- `ai_briefing_enabled`
- `appearance_profile`
- `font_scale`
- `error_log_retention_days`
- `hide_completed_older_than_days`
- `sidebar_visible_modules`
- `morning_briefing_time`
- `weekly_review_time`
- `memory_lock_enabled`
- `sync_enabled`
- `sync_backend_configs`
- `quiet_hours_start`
- `quiet_hours_end`
- `notification_sound_enabled`
- `notification_muted_lists`
- `week_starts_on`
- `calendar_view_mode`
- `sidebar_hide_empty_lists`
- `widget_app_group_id`
- `widget_hide_titles`
- `focus_window_opacity`
- `focus_confirm_skip_break`
- `focus_confirm_exit`
- `focus_break_end_alert`

This search does not prove that every remaining key is fully implemented; it
only proves that these 26 have no key-specific shipping consumer at all.

## Why This Matters Before Freeze

- Generic `set_preference` succeeds for these keys even though no Apple feature
  observes them.
- Several names imply privacy or security controls. In particular,
  `memory_lock_enabled` has no Apple biometric/local-auth gate, and
  `widget_hide_titles` does not drive widget redaction.
- Notification scheduling always assigns a default sound and has no consumer
  for `notification_sound_enabled`, muted-list, or quiet-hour keys.
- If an unvalidated arbitrary JSON value syncs today and the feature is
  implemented later, the new code inherits a legacy-value parsing and migration
  problem on day one.
- Every synced natural key also adds another enumerable deterministic CloudKit
  record name, connecting this finding to the metadata issue in
  [CLOUDKIT_RECORD_ID.md](CLOUDKIT_RECORD_ID.md).

## Freeze Decision

Classify each registry-only key as one of:

1. implemented now, with typed validation and behavioral tests;
2. rejected/removed from the Apple write allowlist until implemented; or
3. intentionally reserved, but rejected for writes and sync until a versioned
   value contract exists.

Because the `preferences` table and envelope payload are generic, adding a new
key later does not require a SQLite or CloudKit schema migration. There is no
technical need to accept arbitrary values for future settings before their
semantics exist.
