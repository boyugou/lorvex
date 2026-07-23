import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

import { repoRoot } from "./shared.mjs";

const legacyPath = path.join(
  repoRoot,
  "lorvex-sync/src/apply/aggregate/tests.rs",
);
const moduleDir = path.join(repoRoot, "lorvex-sync/src/apply/aggregate/tests");

function read(relativePath) {
  return fs.readFileSync(path.join(moduleDir, relativePath), "utf8");
}

const expectedTestNames = [
  "absent_ai_notes_preserves_existing_value",
  "absent_archived_at_preserves_existing_value",
  "absent_body_key_is_treated_as_null_no_op_merge",
  "absent_body_preserves_existing_value",
  "absent_canonical_occurrence_date_preserves_existing_value",
  "absent_completed_at_preserves_existing_value",
  "absent_defer_count_preserves_existing_value",
  "absent_due_date_preserves_existing_value",
  "absent_due_time_preserves_existing_value",
  "absent_estimated_minutes_preserves_existing_value",
  "absent_last_defer_reason_preserves_existing_value",
  "absent_last_deferred_at_preserves_existing_value",
  "absent_planned_date_preserves_existing_value",
  "absent_priority_preserves_existing_value",
  "absent_raw_input_preserves_existing_value",
  "absent_recurrence_exceptions_preserves_existing_value",
  "absent_recurrence_group_id_preserves_existing_value",
  "absent_recurrence_instance_key_preserves_existing_value",
  "absent_recurrence_preserves_existing_value",
  "absent_spawned_from_preserves_existing_value",
  "email_collision_with_attendee_extras_does_not_fuse_metadata",
  "email_collision_with_different_status_resolves_deterministically",
  "explicit_empty_body_is_applied_as_sql_null_clear",
  "explicit_empty_tag_color_is_applied_as_sql_null_clear",
  "explicit_null_clears_value_through_partial_update_path",
  "memory_apply_caps_incoming_content_at_max",
  "memory_apply_logs_conflict_on_truncation",
  "memory_apply_preserves_utf8_char_boundaries_when_truncating",
  "memory_apply_under_cap_is_not_truncated_or_logged",
  "removing_attendee_purges_shadow_row",
  "single_attendee_no_collision_baseline_logs_no_conflict",
  "three_way_email_collision_emits_two_loser_log_rows",
  "underscore_partstat_is_rejected_as_invalid_payload",
  "unknown_attendee_field_round_trips_through_shadow",
  "unrecognized_partstat_value_is_rejected_as_invalid_payload",
].sort();

function testNamesIn(relativePath) {
  return [
    ...read(relativePath).matchAll(
      /^#\[test\]\n(?:#\[[^\n]+\]\n)*fn\s+([a-zA-Z0-9_]+)\s*\(/gm,
    ),
  ].map((match) => match[1]);
}

test("lorvex-sync aggregate apply tests are split by behavior domain", () => {
  assert.ok(
    !fs.existsSync(legacyPath),
    "aggregate apply tests should use tests/mod.rs, not the old 1200+ line tests.rs hotspot",
  );

  const rootSource = read("mod.rs");
  assert.ok(
    rootSource.split("\n").length <= 80,
    "apply/aggregate/tests/mod.rs should stay a small test facade",
  );

  for (const moduleName of [
    "attendee_forward_compat",
    "explicit_empty",
    "memory_cap",
    "partial_update_preservation",
    "support",
  ]) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, "m"),
      `apply/aggregate/tests/mod.rs should register ${moduleName}.rs`,
    );
    assert.ok(
      fs.existsSync(path.join(moduleDir, `${moduleName}.rs`)),
      `${moduleName}.rs should exist under lorvex-sync/src/apply/aggregate/tests/`,
    );
  }

  assert.match(read("support.rs"), /\npub\(super\) fn next_version\b/);
  assert.match(read("support.rs"), /\npub\(super\) fn seed_list\b/);
  assert.match(
    read("explicit_empty.rs"),
    /\bfn\s+explicit_empty_body_is_applied_as_sql_null_clear\b/,
  );
  assert.match(
    read("attendee_forward_compat.rs"),
    /\bfn\s+unknown_attendee_field_round_trips_through_shadow\b/,
  );
  assert.match(
    read("attendee_forward_compat.rs"),
    /\bfn\s+email_collision_with_attendee_extras_does_not_fuse_metadata\b/,
  );
  assert.match(
    read("memory_cap.rs"),
    /\bfn\s+memory_apply_caps_incoming_content_at_max\b/,
  );
  assert.match(
    read("partial_update_preservation.rs"),
    /\bfn\s+absent_archived_at_preserves_existing_value\b/,
  );

  const actualTestNames = [
    "attendee_forward_compat.rs",
    "explicit_empty.rs",
    "memory_cap.rs",
    "partial_update_preservation.rs",
  ]
    .flatMap(testNamesIn)
    .sort();
  assert.deepEqual(
    actualTestNames,
    expectedTestNames,
    "split aggregate apply test modules should preserve the complete migrated test-name set",
  );
});
