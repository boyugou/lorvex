import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, rustModuleDeclarationFileNames } from './shared.mjs';

const legacyTestsPath = path.join(repoRoot, 'lorvex-store/src/repositories/task/read/tests.rs');
const testsDir = path.join(repoRoot, 'lorvex-store/src/repositories/task/read/tests');
const modPath = path.join(testsDir, 'mod.rs');

function read(relativePath) {
  return fs.readFileSync(path.join(testsDir, relativePath), 'utf8');
}

test('task_repo tests are organized by query domain instead of one hotspot file', () => {
  assert.ok(!fs.existsSync(legacyTestsPath), 'task_repo/tests.rs should be replaced by tests/');
  assert.ok(fs.existsSync(modPath), 'task_repo/tests/mod.rs should register focused test modules');

  const modSource = fs.readFileSync(modPath, 'utf8');
  assert.deepEqual(
    fs
      .readdirSync(testsDir)
      .filter((fileName) => fileName.endsWith('.rs'))
      .sort(),
    rustModuleDeclarationFileNames(modSource),
    'task_repo tests module file set drifted',
  );
  // The previously consolidated `date_queries` test file was further split
  // into focused per-bucket modules (today / overdue / upcoming /
  // bucket_counts) plus an ordering module.
  const moduleNames = rustModuleDeclarationFileNames(modSource, { includeRoot: false })
    .map((fileName) => fileName.replace(/\.rs$/, ''));
  for (const moduleName of moduleNames) {
    assert.match(
      modSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `tests/mod.rs should register ${moduleName}.rs`,
    );
  }

  const supportSource = read('support.rs');
  assert.match(supportSource, /\npub\(super\) fn insert_task\b/);
  assert.match(supportSource, /\npub\(super\) fn insert_list\b/);

  const listFiltersSource = read('list_filters.rs');
  assert.match(listFiltersSource, /\bfn\s+list_tasks_filters_status_tags_text_and_counts_total\b/);
  assert.match(listFiltersSource, /\bfn\s+list_tasks_dependency_filters_ignore_archived_endpoints\b/);
  assert.match(listFiltersSource, /\bfn\s+priority_due_desc_pushes_unprioritized_last\b/);

  const orderingSource = read('ordering.rs');
  assert.match(orderingSource, /\bfn\s+task_order_by_is_id_stable_canonical\b/);

  const todaySource = read('today.rs');
  assert.match(todaySource, /\bfn\s+today_returns_planned_date_lte_today\b/);

  const bucketCountsSource = read('bucket_counts.rs');
  assert.match(bucketCountsSource, /\bfn\s+count_open_task_day_buckets_matches_canonical_bucket_queries\b/);
  assert.match(bucketCountsSource, /\bfn\s+high_priority_undated_returns_p1_p2_without_dates\b/);

  const searchSource = read('search.rs');
  assert.match(searchSource, /\bfn\s+search_finds_by_title\b/);
  assert.match(searchSource, /\bfn\s+search_fts_matches_tag_display_name\b/);
  assert.match(searchSource, /\bfn\s+fts_tag_unlink_removes_from_index\b/);

  const trigramSource = read('trigram.rs');
  assert.match(trigramSource, /\bfn\s+search_trigram_finds_cjk_substring_across_indexed_columns\b/);
  assert.match(trigramSource, /\bfn\s+search_trigram_handles_5000_cjk_tasks_quickly\b/);

  const wireDueAtSource = read('wire_due_at.rs');
  assert.match(wireDueAtSource, /\bfn\s+task_scheduling_serializes_at_moment_with_flat_legacy_keys\b/);
  assert.match(wireDueAtSource, /\bfn\s+task_scheduling_serializes_unscheduled_with_no_due_keys\b/);
});
