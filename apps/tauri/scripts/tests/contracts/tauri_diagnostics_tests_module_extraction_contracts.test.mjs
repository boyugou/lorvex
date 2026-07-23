import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

import { readRustSources, repoRoot } from "./shared.mjs";

const diagnosticsFacadePath = path.join(
  repoRoot,
  "app/src-tauri/src/commands/tests/diagnostics.rs",
);
const diagnosticsModulesPath = path.join(
  repoRoot,
  "app/src-tauri/src/commands/tests/diagnostics",
);

function readFacade() {
  return fs.readFileSync(diagnosticsFacadePath, "utf8");
}

function readModule(name) {
  return fs.readFileSync(
    path.join(diagnosticsModulesPath, `${name}.rs`),
    "utf8",
  );
}

function assertTestInModule(moduleName, testName) {
  assert.match(
    readModule(moduleName),
    new RegExp(`#\\[test\\]\\s*fn ${testName}\\(`),
    `${moduleName}.rs should own ${testName}`,
  );
}

test("Tauri diagnostics command tests are split into focused modules", () => {
  const facadeSource = readFacade();
  const expectedModules = [
    "changelog",
    "diagnostic_queries",
    "error_logs",
    "retention_cleanup",
    "retention_preferences",
    "support",
    "sync_state",
  ];

  assert.equal(
    fs.existsSync(diagnosticsModulesPath),
    true,
    "diagnostics command tests should live in a diagnostics/ module tree",
  );
  const moduleTreeSource = readRustSources(
    "app/src-tauri/src/commands/tests/diagnostics",
  );
  assert.doesNotMatch(
    facadeSource,
    /#\[test\]/,
    "diagnostics.rs should be a small facade, not a monolithic test file",
  );

  for (const moduleName of expectedModules) {
    assert.match(
      facadeSource,
      new RegExp(`^mod ${moduleName};$`, "m"),
      `diagnostics.rs should register ${moduleName}.rs`,
    );
  }

  assert.match(
    readModule("support"),
    /pub\(super\) use super::super::\*;/,
    "diagnostics/support.rs should bridge the parent command-test helpers",
  );

  for (const testName of [
    "append_error_log_internal_writes_normalized_entries",
    "append_error_log_internal_rejects_empty_source_or_message",
    "append_error_log_redacts_bearer_tokens_at_write_time",
    "append_error_log_redacts_api_key_prefixes_and_json_secrets",
    "clear_error_logs_removes_all_rows",
  ]) {
    assertTestInModule("error_logs", testName);
  }

  for (const testName of [
    "ai_changelog_filters_human_actor_aliases",
    "ai_changelog_entity_id_filter_narrows_to_one_entity",
  ]) {
    assertTestInModule("changelog", testName);
  }

  for (const testName of [
    "read_changelog_retention_days_surfaces_preference_lookup_failures",
    "read_changelog_retention_days_rejects_invalid_preference",
    "read_changelog_retention_days_accepts_all_ui_offered_values",
    "read_changelog_retention_days_returns_none_when_unset",
    "read_retention_days_surfaces_preference_lookup_failures",
    "read_retention_days_rejects_invalid_preference",
    "read_retention_days_rejects_non_positive_preference",
    "read_retention_days_accepts_canonical_json_number",
  ]) {
    assertTestInModule("retention_preferences", testName);
  }

  for (const testName of [
    "run_data_retention_cleanup_deletes_rfc3339_boundary_rows",
    "run_data_retention_cleanup_applies_defaults_when_no_preferences_set",
    "run_data_retention_cleanup_logs_swallowed_outbox_gc_failure",
    "run_data_retention_cleanup_reaps_stale_pending_queues_via_production_path",
  ]) {
    assertTestInModule("retention_cleanup", testName);
  }

  for (const testName of [
    "read_sync_conflict_log_returns_newest_first_with_limit",
  ]) {
    assertTestInModule("sync_state", testName);
  }

  for (const testName of [
    "read_error_logs_since_iso_filter_narrows_the_window",
    "read_diagnostics_device_ids_returns_distinct_ids_ordered_by_recency",
    "read_unseen_error_log_count_respects_last_viewed_marker",
    "error_logs_command_does_not_advertise_ignored_source_device_filter",
  ]) {
    assertTestInModule("diagnostic_queries", testName);
  }

  const testNames = Array.from(
    moduleTreeSource.matchAll(/#\[test\]\s*fn\s+([a-zA-Z0-9_]+)\(/g),
    (match) => match[1],
  );
  assert.equal(
    testNames.length,
    24,
    "diagnostics/ should keep the existing diagnostics command regression count",
  );
  assert.equal(
    new Set(testNames).size,
    24,
    "diagnostics/ should not duplicate diagnostics command regression names",
  );
});
