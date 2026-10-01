# Local Preference Registry Audit

Source type: Lorvex source audit; no external webpage

Last verified: 2026-09-30 against `main`

## Contract Shape

`PreferenceKeys.allKnownPreferenceKeys` is not just documentation. It is the
write allowlist used by system/App Intent and MCP preference surfaces. A key in
the list is validated by `PreferenceValueContract`, stored as canonical JSON,
exported, and — unless it is in `localOnlyPreferenceKeys` or is the virtual
control-plane key `ai_changelog_retention_policy` — synchronized as a CloudKit
`preference` entity.

Tests also enumerate the registry, turning the set into an intentional
compatibility contract.

## Registry Contents

The registry defines 11 keys: `working_hours`, `timezone`, `default_list_id`,
`ai_changelog_retention_policy`, `language`, `theme`, `setup_completed`,
`setup_summary`, `setup_state`, `record_raw_input`, and
`notification_show_task_notes`. Each has a shipping Swift consumer outside
`PreferenceKeys.swift`.

A key with no consumer is not registered, so generic `set_preference` never
succeeds for a setting that no Apple feature observes. Names that imply privacy
or security controls (a memory lock, hidden widget titles) are absent for the
same reason. `PreferenceKeysTests` asserts that the keys removed for having no
consumer stay rejected by the allowlist.

## Rule for Adding a Key

Every synced natural key adds another enumerable deterministic CloudKit record
name, connecting the registry to the metadata issue in
[CLOUDKIT_RECORD_ID.md](CLOUDKIT_RECORD_ID.md). A key therefore joins the
registry only together with a consumer and a typed value validator.

Because the `preferences` table and envelope payload are generic, adding a new
key does not require a SQLite or CloudKit schema migration. There is no
technical need to accept arbitrary values for future settings before their
semantics exist.
