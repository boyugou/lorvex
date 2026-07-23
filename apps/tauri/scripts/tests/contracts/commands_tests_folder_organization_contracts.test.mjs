import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

import { readRustSources, repoRoot } from "./shared.mjs";

test("tauri commands tests live in a module tree instead of one shattered root file", () => {
  const commandsSource = fs.readFileSync(
    path.join(repoRoot, "app/src-tauri/src/commands.rs"),
    "utf8",
  );
  const testsModSource = fs.readFileSync(
    path.join(repoRoot, "app/src-tauri/src/commands/tests/mod.rs"),
    "utf8",
  );
  const calendarSource = fs.readFileSync(
    path.join(repoRoot, "app/src-tauri/src/commands/tests/calendar.rs"),
    "utf8",
  );
  const dayContextSource = fs.readFileSync(
    path.join(repoRoot, "app/src-tauri/src/commands/tests/day_context.rs"),
    "utf8",
  );
  const diagnosticsSource = readRustSources(
    "app/src-tauri/src/commands/tests/diagnostics",
  );
  const scaleSmokeModSource = fs.readFileSync(
    path.join(repoRoot, "app/src-tauri/src/commands/tests/scale_smoke/mod.rs"),
    "utf8",
  );
  const scaleSmokeDatasetSource = fs.readFileSync(
    path.join(
      repoRoot,
      "app/src-tauri/src/commands/tests/scale_smoke/dataset.rs",
    ),
    "utf8",
  );
  const scaleSmokeMetricsSource = fs.readFileSync(
    path.join(
      repoRoot,
      "app/src-tauri/src/commands/tests/scale_smoke/metrics.rs",
    ),
    "utf8",
  );
  const scaleSmokeRegressionSource = fs.readFileSync(
    path.join(
      repoRoot,
      "app/src-tauri/src/commands/tests/scale_smoke/regressions.rs",
    ),
    "utf8",
  );
  const syncTestsRoot = fs.readFileSync(
    path.join(repoRoot, "app/src-tauri/src/commands/tests/sync/mod.rs"),
    "utf8",
  );
  const syncFilesystemBridgeRoot = fs.readFileSync(
    path.join(
      repoRoot,
      "app/src-tauri/src/commands/tests/sync/filesystem_bridge/mod.rs",
    ),
    "utf8",
  );
  const syncStatusRoot = fs.readFileSync(
    path.join(repoRoot, "app/src-tauri/src/commands/tests/sync/status/mod.rs"),
    "utf8",
  );
  const taskRuntimeRootSource = fs.readFileSync(
    path.join(repoRoot, "app/src-tauri/src/commands/tests/task_runtime/mod.rs"),
    "utf8",
  );
  const taskRuntimeSource = readRustSources(
    "app/src-tauri/src/commands/tests/task_runtime",
  );

  assert.match(commandsSource, /^#\[cfg\(test\)\]\s*mod tests;$/m);
  assert.equal(
    fs.existsSync(path.join(repoRoot, "app/src-tauri/src/commands/tests.rs")),
    false,
    "commands/tests.rs should be replaced by a tests/ module tree",
  );

  for (const moduleName of [
    "calendar",
    "day_context",
    "diagnostics",
    "lists",
    "overview",
    "planning",
    "provider_links",
    "reviews",
    "scale_smoke",
    "sync",
    "task_commands",
    "task_runtime",
  ]) {
    assert.match(
      testsModSource,
      new RegExp(`^mod ${moduleName};$`, "m"),
      `commands/tests/mod.rs should register ${moduleName}`,
    );
  }

  assert.match(
    calendarSource,
    /fn normalize_calendar_recurrence_rejects_invalid_payload\([\s\S]*fn update_calendar_event_all_day_clears_persisted_times\(/,
    "calendar.rs should own calendar recurrence and event-write regressions",
  );
  assert.match(
    dayContextSource,
    /fn normalize_date_input_converts_rfc3339_to_target_local_calendar_day\([\s\S]*fn query_list_tasks_with_recent_completed_excludes_rows_outside_retention_window\(/,
    "day_context.rs should own local-day and retention-window regressions",
  );
  assert.match(
    diagnosticsSource,
    /fn append_error_log_internal_writes_normalized_entries\(/,
    "diagnostics/ should own error-log regressions",
  );
  assert.match(
    diagnosticsSource,
    /fn ai_changelog_filters_human_actor_aliases\(/,
    "diagnostics/ should own changelog filtering regressions",
  );
  assert.match(
    scaleSmokeModSource,
    /^mod dataset;$/m,
    "scale_smoke/mod.rs should register the dataset helper module",
  );
  assert.match(
    scaleSmokeModSource,
    /^mod metrics;$/m,
    "scale_smoke/mod.rs should register the metrics helper module",
  );
  assert.match(
    scaleSmokeModSource,
    /^mod regressions;$/m,
    "scale_smoke/mod.rs should register the regression cases module",
  );
  assert.match(
    scaleSmokeDatasetSource,
    /pub\(super\) fn seed_scale_smoke_dataset\(/,
    "scale_smoke dataset module should own synthetic dataset seeding",
  );
  assert.match(
    scaleSmokeMetricsSource,
    /pub\(super\) fn collect_scale_smoke_metrics\([\s\S]*pub\(super\) fn assert_scale_smoke_metrics\(/,
    "scale_smoke metrics module should own collection and assertion helpers",
  );
  assert.match(
    scaleSmokeRegressionSource,
    /fn app_scale_smoke_queries_remain_responsive_at_1k_dataset\([\s\S]*fn app_scale_smoke_queries_remain_responsive_at_10k_dataset\(/,
    "scale_smoke regression module should own dataset-size throughput regressions",
  );
  assert.match(
    taskRuntimeRootSource,
    /^mod all_tasks;$/m,
    "task_runtime/mod.rs should register the all_tasks regression module",
  );
  assert.match(
    taskRuntimeRootSource,
    /^mod dependencies;$/m,
    "task_runtime/mod.rs should register the dependencies regression module",
  );
  assert.match(
    taskRuntimeRootSource,
    /^mod list_deletion;$/m,
    "task_runtime/mod.rs should register the list_deletion regression module",
  );
  assert.match(
    taskRuntimeSource,
    /fn build_get_all_tasks_sql_includes_completed_within_limit\([\s\S]*fn cleanup_task_dependency_refs_removes_edges\([\s\S]*fn delete_list_internal_rejects_assigned_tasks\(/,
    "task_runtime/ should own task query, dependency cleanup, and list deletion regressions that match the current list deletion contract",
  );
  assert.equal(
    fs.existsSync(path.join(repoRoot, "app/src-tauri/src/commands/tests/widget_snapshot")),
    false,
    "Tauri must not keep the retired Apple widget snapshot command tests",
  );
  assert.equal(
    fs.existsSync(
      path.join(repoRoot, "app/src-tauri/src/commands/tests/sync.rs"),
    ),
    false,
    "commands/tests/sync.rs should be replaced by a sync/ folder tree",
  );
  for (const moduleName of [
    "core",
    "filesystem_bridge",
    "remote_apply",
    "status",
    "timestamp_format",
  ]) {
    assert.match(
      syncTestsRoot,
      new RegExp(`^mod ${moduleName};$`, "m"),
      `commands/tests/sync/mod.rs should register ${moduleName}.rs`,
    );
  }
  for (const moduleName of [
    "collection_delayed",
    "collection_filtering",
    "collection_lookback",
    "collection_ordering",
    "cursor",
    "filesystem_bridge_root_path",
  ]) {
    assert.match(
      syncFilesystemBridgeRoot,
      new RegExp(`^mod ${moduleName};$`, "m"),
      `commands/tests/sync/filesystem_bridge/mod.rs should register ${moduleName}.rs`,
    );
  }
  for (const moduleName of [
    "core_deletions",
    "core_event_state",
    "core_helpers",
    "loading_cursors",
    "loading_ical_subscriptions",
    "loading_lookback",
    "loading_pending_inbox",
    "loading_retention",
    "loading_timestamps",
    "timestamps",
  ]) {
    assert.match(
      syncStatusRoot,
      new RegExp(`^mod ${moduleName};$`, "m"),
      `commands/tests/sync/status/mod.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(
    fs.readFileSync(
      path.join(
        repoRoot,
        "app/src-tauri/src/commands/tests/sync/timestamp_format.rs",
      ),
      "utf8",
    ),
    /fn sync_timestamp_now_format_is_(?:milli|micro)second_z_suffix\([\s\S]*fn sync_timestamps_are_lexicographically_ordered\(/,
    "sync/timestamp_format.rs should own sync timestamp formatting regressions",
  );
  assert.match(
    readRustSources(
      "app/src-tauri/src/commands/tests/sync/filesystem_bridge/filesystem_bridge_root_path.rs",
    ),
    /fn resolve_filesystem_bridge_root_path_expands_home_prefix\(/,
    "sync/filesystem_bridge/ should cover root-path normalization regressions",
  );
  assert.match(
    readRustSources(
      "app/src-tauri/src/commands/tests/sync/filesystem_bridge/cursor.rs",
    ),
    /fn load_filesystem_bridge_pull_cursor_rejects_malformed_state\(/,
    "sync/filesystem_bridge/ should cover cursor validation regressions",
  );
  assert.match(
    readRustSources(
      "app/src-tauri/src/commands/tests/sync/filesystem_bridge",
    ),
    /fn delayed_event_at_or_behind_cursor_is_accounted_as_stale_when_newer_entity_exists\(/,
    "sync/filesystem_bridge/ should cover delayed-event stale accounting regressions",
  );
  assert.match(
    readRustSources(
      "app/src-tauri/src/commands/tests/sync/filesystem_bridge",
    ),
    /fn collect_remote_filesystem_bridge_envelopes_lookback_skips_known_event_ids\(/,
    "sync/filesystem_bridge/ should cover cursor lookback regressions",
  );
  assert.match(
    readRustSources(
      "app/src-tauri/src/commands/tests/sync/filesystem_bridge",
    ),
    /fn collect_remote_filesystem_bridge_envelopes_is_deterministic_under_pull_cap\(/,
    "sync/filesystem_bridge/ should own path resolution, cursor validation, delayed-event lookback, and deterministic collection regressions",
  );
  assert.match(
    readRustSources("app/src-tauri/src/commands/tests/sync/status"),
    /fn mark_task_cancelled_marks_status_cancelled_without_removing_row\(/,
    "sync/status/core/ should cover deletion semantics regressions",
  );
  assert.match(
    readRustSources("app/src-tauri/src/commands/tests/sync/status"),
    /fn mark_outbox_entries_synced_is_idempotent_and_clears_last_error\(/,
    "sync/status/core/ should cover sync event-state regressions",
  );
  assert.match(
    readRustSources("app/src-tauri/src/commands/tests/sync/status"),
    /fn load_sync_status_from_conn_separates_raw_parsed_and_effective_sync_backend_kind\(/,
    "sync/status/loading/ should cover backend status separation regressions",
  );
  assert.match(
    readRustSources("app/src-tauri/src/commands/tests/sync/status"),
    /fn load_sync_status_from_conn_flags_malformed_lookback_known_id_skip_metric\(/,
    "sync/status/loading/ should cover malformed lookback diagnostics regressions",
  );
  assert.match(
    readRustSources(
      "app/src-tauri/src/commands/tests/sync/status/timestamps.rs",
    ),
    /fn sync_checkpoints_survives_offline_online_transition_without_timestamp_regression\(/,
    "sync/status/ should own deletion/event-state semantics, backend status separation, malformed lookback diagnostics, and checkpoint timestamp regressions",
  );
});
