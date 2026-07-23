import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('mcp server tests live in a coherent folder tree instead of one monolith file', () => {
  const testsDir = path.join(repoRoot, 'mcp-server/src/server/tests');
  const testsRoot = fs.readFileSync(path.join(testsDir, 'mod.rs'), 'utf8');
  const tasksRootSource = fs.readFileSync(path.join(testsDir, 'tasks/mod.rs'), 'utf8');
  const taskReadMutationRootSource = fs.readFileSync(
    path.join(testsDir, 'tasks/read_and_mutation_validation.rs'),
    'utf8',
  );
  const taskReadMutationReadErrorsSource = fs.readFileSync(
    path.join(testsDir, 'tasks/read_and_mutation_validation/read_errors.rs'),
    'utf8',
  );
  const taskReadMutationPrioritySource = fs.readFileSync(
    path.join(testsDir, 'tasks/read_and_mutation_validation/priority.rs'),
    'utf8',
  );
  const taskRecurrenceSource = fs.readFileSync(
    path.join(testsDir, 'tasks/recurrence.rs'),
    'utf8',
  );
  const calendarSource = fs.readFileSync(path.join(testsDir, 'calendar.rs'), 'utf8');
  const listsOverviewRootSource = fs.readFileSync(
    path.join(testsDir, 'lists_overview/mod.rs'),
    'utf8',
  );
  const listsSource = fs.readFileSync(
    path.join(testsDir, 'lists_overview/lists.rs'),
    'utf8',
  );
  const overviewRootSource = fs.readFileSync(
    path.join(testsDir, 'lists_overview/overview/mod.rs'),
    'utf8',
  );
  const overviewHealthSource = fs.readFileSync(
    path.join(testsDir, 'lists_overview/overview/health_snapshot.rs'),
    'utf8',
  );
  const overviewTodaySource = fs.readFileSync(
    path.join(testsDir, 'lists_overview/overview/todays_tasks.rs'),
    'utf8',
  );
  const overviewCompactSource = fs.readFileSync(
    path.join(testsDir, 'lists_overview/overview/compact.rs'),
    'utf8',
  );
  const weeklyReviewSource = fs.readFileSync(
    path.join(testsDir, 'lists_overview/weekly_review.rs'),
    'utf8',
  );
  const planningRootSource = fs.readFileSync(path.join(testsDir, 'planning/mod.rs'), 'utf8');
  const planningAcceptanceSource = fs.readFileSync(
    path.join(testsDir, 'planning/acceptance.rs'),
    'utf8',
  );
  const planningFailuresSource = fs.readFileSync(
    path.join(testsDir, 'planning/failures.rs'),
    'utf8',
  );
  const triageLogsRootSource = fs.readFileSync(
    path.join(testsDir, 'triage_and_logs/mod.rs'),
    'utf8',
  );
  const triageLogsMemorySource = fs.readFileSync(
    path.join(testsDir, 'triage_and_logs/memory.rs'),
    'utf8',
  );
  const triageLogsSource = fs.readFileSync(
    path.join(testsDir, 'triage_and_logs/logs.rs'),
    'utf8',
  );

  assert.equal(
    fs.existsSync(path.join(repoRoot, 'mcp-server/src/server/tests.rs')),
    false,
    'server/tests.rs should be replaced by a tests/ folder tree',
  );

  for (const moduleName of [
    'calendar',
    'guidance',
    'lists_overview',
    'overview_setup',
    'planning',
    'tasks',
    'triage_and_logs',
    'weekly_review',
  ]) {
    assert.match(
      testsRoot,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `server/tests/mod.rs should register ${moduleName}.rs`,
    );
  }

  assert.match(
    tasksRootSource,
    /^mod read_and_mutation_validation;$/m,
    'tasks/mod.rs should register the task read/mutation validation module',
  );
  assert.match(
    tasksRootSource,
    /^mod recurrence;$/m,
    'tasks/mod.rs should register the recurrence validation module',
  );
  assert.match(
    tasksRootSource,
    /^mod reminders;$/m,
    'tasks/mod.rs should register the reminders test module',
  );
  assert.match(
    tasksRootSource,
    /^mod sync_failures;$/m,
    'tasks/mod.rs should register the sync failures test module',
  );
  assert.doesNotMatch(
    tasksRootSource,
    /\nfn get_task_missing_returns_not_found_error_text\(|\nfn set_recurrence_rejects_invalid_until_dates\(/,
    'tasks/mod.rs should remain a composition root after folder extraction',
  );
  for (const moduleName of ['read_errors', 'priority']) {
    assert.match(
      taskReadMutationRootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `tasks/read_and_mutation_validation.rs should register ${moduleName}.rs`,
    );
  }
  assert.doesNotMatch(
    taskReadMutationRootSource,
    /\nfn get_task_missing_returns_not_found_error_text\(|\nfn batch_create_tasks_rejects_priority_outside_allowed_range\(/,
    'tasks/read_and_mutation_validation.rs should remain a composition root',
  );
  assert.match(
    taskReadMutationReadErrorsSource,
    /fn get_task_missing_returns_not_found_error_text\(/,
    'tasks/read_and_mutation_validation/read_errors.rs should own read error regressions',
  );
  assert.match(
    taskReadMutationPrioritySource,
    /fn create_task_rejects_priority_outside_allowed_range\([\s\S]*fn batch_create_tasks_rejects_priority_outside_allowed_range\(/,
    'tasks/read_and_mutation_validation/priority.rs should own priority validation regressions',
  );
  assert.match(
    taskRecurrenceSource,
    /fn set_recurrence_rejects_invalid_until_dates\(/,
    'tasks/recurrence.rs should own recurrence validation regressions',
  );
  assert.match(
    calendarSource,
    /fn update_calendar_event_rejects_non_weekly_byday_recurrence\(/,
    'calendar.rs should own calendar tool regressions',
  );
  assert.match(
    listsOverviewRootSource,
    /^mod lists;$/m,
    'lists_overview/mod.rs should register the list payload test module',
  );
  assert.match(
    listsOverviewRootSource,
    /^mod overview;$/m,
    'lists_overview/mod.rs should register the overview test module',
  );
  assert.match(
    listsOverviewRootSource,
    /^mod weekly_review;$/m,
    'lists_overview/mod.rs should register the weekly review test module',
  );
  assert.doesNotMatch(
    listsOverviewRootSource,
    /\nfn get_list_returns_bounded_payload_with_truncation_metadata\(|\nfn get_overview_compact_returns_bounded_payload\(|\nfn get_weekly_review_snapshot_is_bounded_and_high_signal\(/,
    'lists_overview/mod.rs should remain a composition root after folder extraction',
  );
  assert.match(
    listsSource,
    /fn get_list_returns_bounded_payload_with_truncation_metadata\([\s\S]*fn get_list_excludes_completed_tasks_older_than_retention_window\(/,
    'lists_overview/lists.rs should own list payload regressions',
  );
  assert.match(
    overviewRootSource,
    /^mod compact;$/m,
    'lists_overview/overview/mod.rs should register the compact overview regression module',
  );
  assert.match(
    overviewRootSource,
    /^mod health_snapshot;$/m,
    'lists_overview/overview/mod.rs should register the list-health regression module',
  );
  assert.match(
    overviewRootSource,
    /^mod todays_tasks;$/m,
    'lists_overview/overview/mod.rs should register the todays-tasks regression module',
  );
  assert.doesNotMatch(
    overviewRootSource,
    /\nfn get_list_health_snapshot_returns_bounded_counts_and_compact_names\(|\nfn get_todays_tasks_exposes_bucket_summary_and_truncation\(|\nfn get_overview_compact_returns_bounded_payload\(/,
    'lists_overview/overview/mod.rs should remain a composition root after internal test split',
  );
  assert.match(
    overviewHealthSource,
    /fn get_list_health_snapshot_returns_bounded_counts_and_compact_names\([\s\S]*fn get_list_health_snapshot_applies_default_and_cap_limits\(/,
    'lists_overview/overview/health_snapshot.rs should own list-health regressions',
  );
  assert.match(
    overviewTodaySource,
    /fn get_todays_tasks_exposes_bucket_summary_and_truncation\(/,
    'lists_overview/overview/todays_tasks.rs should own today-bucket overview regressions',
  );
  assert.match(
    overviewCompactSource,
    /fn get_overview_compact_returns_bounded_payload\(/,
    'lists_overview/overview/compact.rs should own compact overview regressions',
  );
  assert.match(
    weeklyReviewSource,
    /fn get_weekly_review_snapshot_is_bounded_and_high_signal\(/,
    'lists_overview/weekly_review.rs should own weekly review snapshot regressions',
  );
  assert.match(
    planningRootSource,
    /^mod acceptance;$/m,
    'planning/mod.rs should register the acceptance test module',
  );
  assert.match(
    planningRootSource,
    /^mod failures;$/m,
    'planning/mod.rs should register the failure-path test module',
  );
  assert.match(
    planningRootSource,
    /^mod provider_events;$/m,
    'planning/mod.rs should register the provider events test module',
  );
  assert.doesNotMatch(
    planningRootSource,
    /\nfn save_focus_schedule_applies_current_focus\(|\nfn save_focus_schedule_empty_blocks_returns_error\(/,
    'planning/mod.rs should remain a composition root after folder extraction',
  );
  assert.match(
    planningAcceptanceSource,
    /fn save_focus_schedule_applies_current_focus\(/,
    'planning/acceptance.rs should own successful schedule save regressions',
  );
  assert.match(
    planningFailuresSource,
    /fn save_focus_schedule_empty_blocks_returns_error\(/,
    'planning/failures.rs should own validation regressions',
  );
  assert.match(
    triageLogsRootSource,
    /^mod logs;$/m,
    'triage_and_logs/mod.rs should register the logs test module',
  );
  assert.match(
    triageLogsRootSource,
    /^mod memory;$/m,
    'triage_and_logs/mod.rs should register the memory test module',
  );
  assert.doesNotMatch(
    triageLogsRootSource,
    /\nfn write_memory_rolls_back_when_changelog_insert_fails\(|\nfn get_ai_changelog_entity_id_filter_matches_exact_json_array_membership\(/,
    'triage_and_logs/mod.rs should remain a composition root with shared helpers only',
  );
  assert.match(
    triageLogsMemorySource,
    /fn write_memory_rolls_back_when_changelog_insert_fails\(/,
    'triage_and_logs/memory.rs should own write-memory rollback regressions',
  );
  assert.match(
    triageLogsSource,
    /fn get_ai_changelog_entity_id_filter_matches_exact_json_array_membership\([\s\S]*fn get_recent_logs_merges_and_redacts_sources_in_descending_timestamp_order\(/,
    'triage_and_logs/logs.rs should own changelog and recent-log regressions',
  );
});
