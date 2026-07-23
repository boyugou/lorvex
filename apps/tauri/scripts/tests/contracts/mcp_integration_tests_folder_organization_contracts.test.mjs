import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function* walkFiles(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      yield* walkFiles(fullPath);
    } else if (entry.isFile()) {
      yield fullPath;
    }
  }
}

test('MCP integration harness is organized as a folder-backed suite with a shared harness module and domain files', () => {
  const entrySource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration.test.ts'),
    'utf8',
  );
  const sharedSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/shared.ts'),
    'utf8',
  );
  const sharedHarnessSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/shared/harness.ts'),
    'utf8',
  );
  const sharedResultsSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/shared/results.ts'),
    'utf8',
  );
  const sharedTimeSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/shared/time.ts'),
    'utf8',
  );
  const sharedSeedsSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/shared/seeds.ts'),
    'utf8',
  );
  const writePathSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/write_path.ts'),
    'utf8',
  );
  const importExportSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/import_export.ts'),
    'utf8',
  );
  const assistantUiEntrySource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/assistant_ui_and_calendar.ts'),
    'utf8',
  );
  const assistantUiDomainSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/assistant_ui_and_calendar/assistant_ui.ts'),
    'utf8',
  );
  const assistantUiCommandValidationSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/assistant_ui_and_calendar/assistant_ui_cases/command_validation.ts'),
    'utf8',
  );
  const assistantUiLanguageSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/assistant_ui_and_calendar/assistant_ui_cases/language.ts'),
    'utf8',
  );
  const assistantUiPendingCommandsSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/assistant_ui_and_calendar/assistant_ui_cases/pending_commands.ts'),
    'utf8',
  );
  const calendarDomainSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/assistant_ui_and_calendar/calendar.ts'),
    'utf8',
  );
  const queryBoundsSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/query_bounds_and_scale.ts'),
    'utf8',
  );
  const queryBoundsDomainSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/query_bounds_and_scale/bounded_queries.ts'),
    'utf8',
  );
  const queryBoundsListSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/query_bounds_and_scale/bounded_query_cases/list_bounds.ts'),
    'utf8',
  );
  const queryBoundsWeeklyReviewSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/query_bounds_and_scale/bounded_query_cases/weekly_review_bounds.ts'),
    'utf8',
  );
  const queryBoundsHighCardinalitySource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/query_bounds_and_scale/bounded_query_cases/high_cardinality.ts'),
    'utf8',
  );
  const scaleBudgetSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/query_bounds_and_scale/scale_budgets.ts'),
    'utf8',
  );
  const learningEntrySource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/learning_and_schedule.ts'),
    'utf8',
  );
  const learningDomainSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/learning_and_schedule/learning.ts'),
    'utf8',
  );
  const learningMemoryPersistenceSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/learning_and_schedule/learning_cases/memory_persistence.ts'),
    'utf8',
  );
  const learningDeterministicMatrixSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/learning_and_schedule/learning_cases/deterministic_matrix.ts'),
    'utf8',
  );
  const scheduleDomainSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/learning_and_schedule/schedule.ts'),
    'utf8',
  );
  const taskLifecycleSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/task_lifecycle.ts'),
    'utf8',
  );
  const taskLifecycleBatchUpdatesSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/task_lifecycle/batch_updates.ts'),
    'utf8',
  );
  const taskLifecycleCancellationsSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/task_lifecycle/cancellations.ts'),
    'utf8',
  );
  const taskLifecycleNullabilitySource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/task_lifecycle/nullability.ts'),
    'utf8',
  );
  const concurrentWritesContentionSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/mcp/integration/concurrent_writes/contention.ts'),
    'utf8',
  );

  assert.match(entrySource, /^import '\.\/integration\/write_path';$/m);
  assert.match(entrySource, /^import '\.\/integration\/import_export';$/m);
  assert.match(entrySource, /^import '\.\/integration\/assistant_ui_and_calendar';$/m);
  assert.match(entrySource, /^import '\.\/integration\/query_bounds_and_scale';$/m);
  assert.match(entrySource, /^import '\.\/integration\/query_and_diagnostics';$/m);
  assert.match(entrySource, /^import '\.\/integration\/list_mutations';$/m);
  assert.match(entrySource, /^import '\.\/integration\/learning_and_schedule';$/m);
  assert.match(entrySource, /^import '\.\/integration\/task_lifecycle';$/m);
  assert.match(entrySource, /^import '\.\/integration\/workflows';$/m);
  assert.match(entrySource, /^import '\.\/integration\/concurrent_writes';$/m);
  assert.doesNotMatch(
    entrySource,
    /async function createHarness\(|function seedScaleDataset\(|test\('/,
    'integration.test.ts should remain a pure entrypoint after folder extraction',
  );

  assert.match(sharedSource, /^export \{$/m);
  assert.match(sharedSource, /^} from '\.\/shared\/harness';$/m);
  assert.match(sharedSource, /^} from '\.\/shared\/results';$/m);
  assert.match(sharedSource, /^export \{ isoDaysAgo, daysFromTodayYmd \} from '\.\/shared\/time';$/m);
  assert.match(sharedSource, /^} from '\.\/shared\/seeds';$/m);
  assert.doesNotMatch(sharedSource, /async function createHarness\(|function seedScaleDataset\(|function parseJsonContent<|function upsertPreference\(/);
  assert.match(sharedHarnessSource, /\nexport async function createHarness\(/);
  assert.doesNotMatch(sharedHarnessSource, /WIDGET_SHARED_FIXTURE_PATH/);
  assert.match(sharedHarnessSource, /\nexport const TEST_AGENT_NAME = /);
  assert.match(sharedResultsSource, /\nexport function parseJsonContent<T>\(/);
  assert.match(sharedResultsSource, /\nexport function getFirstTextContent\(/);
  assert.match(sharedTimeSource, /^export function daysFromTodayYmd\(/m);
  assert.doesNotMatch(sharedTimeSource, /\blocalDateYmd\b/);
  assert.match(sharedTimeSource, /^export function isoDaysAgo\(/m);
  assert.match(sharedSeedsSource, /\nexport function upsertPreference\(/);
  assert.match(sharedSeedsSource, /\nexport function seedScaleDataset\(/);

  assert.match(writePathSource, /test\('representative write tool persists data and records ai_changelog\/sync_outbox'/);
  assert.equal(
    fs.existsSync(path.join(repoRoot, 'scripts/tests/mcp/integration/write_and_widget.ts')),
    false,
    'Tauri MCP integration tests must not keep the retired write_and_widget suite',
  );
  assert.equal(
    fs.existsSync(path.join(repoRoot, 'scripts/tests/mcp/integration/write_and_widget_cases')),
    false,
    'Tauri MCP integration tests must not keep Apple widget snapshot case files',
  );
  assert.match(importExportSource, /test\('export\/import roundtrip preserves representative records'/);
  assert.match(assistantUiEntrySource, /^import '\.\/assistant_ui_and_calendar\/assistant_ui';$/m);
  assert.match(assistantUiEntrySource, /^import '\.\/assistant_ui_and_calendar\/calendar';$/m);
  assert.doesNotMatch(
    assistantUiEntrySource,
    /test\('/,
    'assistant_ui_and_calendar.ts should remain a barrel entry after folder extraction',
  );
  assert.match(assistantUiDomainSource, /^import '\.\/assistant_ui_cases\/command_validation';$/m);
  assert.match(assistantUiDomainSource, /^import '\.\/assistant_ui_cases\/language';$/m);
  assert.match(assistantUiDomainSource, /^import '\.\/assistant_ui_cases\/pending_commands';$/m);
  assert.doesNotMatch(assistantUiDomainSource, /test\('/);
  assert.match(assistantUiCommandValidationSource, /test\('control_app_ui validates switch_view inputs and writes pending command payloads'/);
  assert.match(assistantUiLanguageSource, /test\('control_app_ui validates and persists set_language commands'/);
  assert.match(assistantUiPendingCommandsSource, /test\('control_app_ui exposes pending command replacement metadata and supports replacement guard'/);
  assert.match(calendarDomainSource, /test\('batch_create_calendar_events creates multiple events and records sync activity once'/);
  assert.match(calendarDomainSource, /test\('create_calendar_event rejects string boolean all_day values under the strict runtime contract'/);
  assert.match(queryBoundsSource, /^import '\.\/query_bounds_and_scale\/bounded_queries';$/m);
  assert.match(queryBoundsSource, /^import '\.\/query_bounds_and_scale\/scale_budgets';$/m);
  assert.doesNotMatch(
    queryBoundsSource,
    /test\('/,
    'query_bounds_and_scale.ts should remain a barrel entry after folder extraction',
  );
  assert.match(queryBoundsDomainSource, /^import '\.\/bounded_query_cases\/list_bounds';$/m);
  assert.match(queryBoundsDomainSource, /^import '\.\/bounded_query_cases\/weekly_review_bounds';$/m);
  assert.match(queryBoundsDomainSource, /^import '\.\/bounded_query_cases\/high_cardinality';$/m);
  assert.doesNotMatch(queryBoundsDomainSource, /test\('/);
  assert.match(queryBoundsListSource, /test\('get_list supports bounded responses with truncation metadata'/);
  assert.match(queryBoundsWeeklyReviewSource, /test\('get_weekly_review_brief supports completed section bounds with metadata'/);
  assert.match(queryBoundsHighCardinalitySource, /test\('high-cardinality query tools remain bounded and expose truncation metadata'/);
  assert.match(scaleBudgetSource, /test\('scale payload budgets remain bounded at 1k and 10k datasets'/);
  assert.match(learningEntrySource, /^import '\.\/learning_and_schedule\/learning';$/m);
  assert.match(learningEntrySource, /^import '\.\/learning_and_schedule\/schedule';$/m);
  assert.doesNotMatch(
    learningEntrySource,
    /test\('/,
    'learning_and_schedule.ts should remain a barrel entry after folder extraction',
  );
  assert.match(learningDomainSource, /^import '\.\/learning_cases\/memory_persistence';$/m);
  assert.match(learningDomainSource, /^import '\.\/learning_cases\/deterministic_matrix';$/m);
  assert.match(learningDomainSource, /^import '\.\/learning_cases\/memory_mutations';$/m);
  assert.doesNotMatch(learningDomainSource, /test\('/);
  assert.match(learningMemoryPersistenceSource, /test\('analyze_task_patterns returns actionable signals with source refs'/);
  assert.match(learningDeterministicMatrixSource, /test\('analyze_task_patterns deterministic matrix covers severity thresholds, top_n, and window filtering'/);
  assert.match(
    fs.readFileSync(
      path.join(repoRoot, 'scripts/tests/mcp/integration/learning_and_schedule/learning_cases/memory_mutations.ts'),
      'utf8',
    ),
    /test\('write_memory and restore_memory_revision round-trip through direct MCP tool calls'/,
  );
  assert.match(taskLifecycleSource, /^import '\.\/task_lifecycle\/advanced_mutations';$/m);
  assert.match(taskLifecycleSource, /^import '\.\/task_lifecycle\/checklists';$/m);
  assert.match(taskLifecycleSource, /^import '\.\/task_lifecycle\/contract_smoke';$/m);
  assert.match(taskLifecycleSource, /^import '\.\/task_lifecycle\/deferrals';$/m);
  assert.match(taskLifecycleSource, /^import '\.\/task_lifecycle\/reminders';$/m);
  assert.match(
    fs.readFileSync(
      path.join(repoRoot, 'scripts/tests/mcp/integration/concurrent_writes.ts'),
      'utf8',
    ),
    /^import '\.\/concurrent_writes\/contention';$/m,
  );
  assert.doesNotMatch(
    fs.readFileSync(
      path.join(repoRoot, 'scripts/tests/mcp/integration/concurrent_writes.ts'),
      'utf8',
    ),
    /test\('/,
  );
  assert.match(concurrentWritesContentionSource, /test\('/);
  assert.match(
    fs.readFileSync(
      path.join(repoRoot, 'scripts/tests/mcp/integration/list_mutations.ts'),
      'utf8',
    ),
    /test\('/,
  );
  assert.match(
    fs.readFileSync(
      path.join(repoRoot, 'scripts/tests/mcp/integration/query_and_diagnostics.ts'),
      'utf8',
    ),
    /test\('/,
  );
  assert.match(
    fs.readFileSync(
      path.join(repoRoot, 'scripts/tests/mcp/integration/workflows.ts'),
      'utf8',
    ),
    /^import '\.\/workflows\/morning_planning';$/m,
  );
  assert.match(
    fs.readFileSync(
      path.join(repoRoot, 'scripts/tests/mcp/integration/workflows.ts'),
      'utf8',
    ),
    /^import '\.\/workflows\/weekly_review';$/m,
  );
  assert.match(
    fs.readFileSync(
      path.join(repoRoot, 'scripts/tests/mcp/integration/workflows.ts'),
      'utf8',
    ),
    /^import '\.\/workflows\/habits';$/m,
  );
  assert.match(
    fs.readFileSync(
      path.join(repoRoot, 'scripts/tests/mcp/integration/workflows.ts'),
      'utf8',
    ),
    /^import '\.\/workflows\/reviews_and_preferences';$/m,
  );
  assert.match(
    fs.readFileSync(
      path.join(repoRoot, 'scripts/tests/mcp/integration/workflows.ts'),
      'utf8',
    ),
    /^import '\.\/workflows\/focus_and_admin';$/m,
  );
  assert.doesNotMatch(
    fs.readFileSync(
      path.join(repoRoot, 'scripts/tests/mcp/integration/workflows.ts'),
      'utf8',
    ),
    /test\('/,
  );
  assert.match(scheduleDomainSource, /test\('propose_daily_schedule deterministic matrix covers defaults, buffers, overflow, and due-date filtering'/);
  assert.match(taskLifecycleSource, /^import '\.\/task_lifecycle\/batch_updates';$/m);
  assert.match(taskLifecycleSource, /^import '\.\/task_lifecycle\/cancellations';$/m);
  assert.match(taskLifecycleSource, /^import '\.\/task_lifecycle\/nullability';$/m);
  assert.doesNotMatch(
    taskLifecycleSource,
    /test\('/,
    'task_lifecycle.ts should remain a barrel entry after folder extraction',
  );
  assert.match(taskLifecycleBatchUpdatesSource, /test\('batch_update_tasks spawns recurrence and propagates dependency changes on completion'/);
  assert.match(taskLifecycleBatchUpdatesSource, /test\('batch_update_tasks propagates depends_on changes'/);
  assert.match(taskLifecycleCancellationsSource, /test\('batch_cancel_tasks_in_list cleans depends_on in other tasks'/);
  assert.match(taskLifecycleCancellationsSource, /test\('update_task clears nullable fields and cleans deps on cancel'/);
  assert.match(taskLifecycleNullabilitySource, /test\('update_task clears nullable text fields via null'/);
  assert.match(taskLifecycleNullabilitySource, /test\('batch_update_tasks clears nullable fields via null'/);
});

test('MCP test sources do not reintroduce the deprecated local-date alias', () => {
  const offenders = [];
  for (const filePath of walkFiles(path.join(repoRoot, 'scripts/tests/mcp'))) {
    if (!/\.(?:ts|mts|js|mjs)$/.test(filePath)) continue;
    const source = fs.readFileSync(filePath, 'utf8');
    if (/\blocalDateYmd\b/.test(source)) {
      offenders.push(path.relative(repoRoot, filePath));
    }
  }

  assert.deepEqual(offenders, []);
});
