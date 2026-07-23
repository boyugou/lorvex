import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const facadePath = path.join(repoRoot, 'lorvex-cli/src/commands/mutate/tags/effects/mod.rs');
const tagsDir = path.join(repoRoot, 'lorvex-cli/src/commands/mutate/tags/effects');

function read(relativePath) {
  return fs.readFileSync(path.join(tagsDir, relativePath), 'utf8');
}

test('lorvex-cli tag DB ops stay split by responsibility', () => {
  const facadeSource = fs.readFileSync(facadePath, 'utf8');
  assert.ok(fs.existsSync(tagsDir), 'mutate/tags/effects/ should contain the extracted tag modules');

  const moduleFiles = fs
    .readdirSync(tagsDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  // After the rename consolidation (replace + rows merged into
  // normalization / rows), the CLI tag effects facade routes:
  //   - normalization: capture-time tag normalization + count validation
  //   - outbox:        sync outbox edge enqueue helpers
  //   - rename:        the transactional rename_tag_with_conn flow
  //   - rows:          shared row loaders consumed by rename + outbox
  //   - tests:         co-located test coverage
  assert.deepEqual(moduleFiles, [
    'mod.rs',
    'normalization.rs',
    'outbox.rs',
    'rename.rs',
    'rows.rs',
    'tests.rs',
  ]);

  for (const moduleName of ['normalization', 'outbox', 'rename', 'rows']) {
    assert.match(
      facadeSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `effects/mod.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(facadeSource, /^#\[cfg\(test\)\]\nmod tests;$/m);

  const facadeLineCount = facadeSource.trimEnd().split('\n').length;
  assert.ok(facadeLineCount <= 55, `effects/mod.rs should stay a thin facade, got ${facadeLineCount} lines`);
  assert.doesNotMatch(
    facadeSource,
    /\n#\[test\]|\nfn\s+\w+|\nstruct\s+\w+|\nimpl\s+/,
    'effects/mod.rs should not keep implementation or tests inline',
  );

  for (const exportName of [
    'enqueue_copied_tag_edges',
    'normalize_capture_tags',
    'rename_tag_with_conn',
    'validate_task_tag_count',
  ]) {
    assert.match(
      facadeSource,
      new RegExp(`\\b${exportName}\\b`),
      `effects/mod.rs should keep ${exportName} reachable from its existing module path`,
    );
  }

  const normalizationSource = read('normalization.rs');
  const dbOpsVisible = String.raw`pub\(crate\)`;
  assert.match(normalizationSource, new RegExp(`\\n${dbOpsVisible} fn normalize_capture_tags\\b`));
  assert.match(normalizationSource, /\n(?:pub\(super\)\s+)?fn normalize_single_tag_name\b/);
  assert.match(normalizationSource, new RegExp(`\\n${dbOpsVisible} fn validate_task_tag_count\\b`));
  assert.doesNotMatch(
    normalizationSource,
    /\nfn\s+rename_tag_with_conn\b|\nenqueue_payload_(?:upsert|delete)\b/,
    'normalization.rs should not own rename transactions or sync outbox writes',
  );

  const rowsSource = read('rows.rs');
  assert.match(rowsSource, /\npub\(super\) struct TaskTagEdgeWithTaskRow\b/);
  assert.match(rowsSource, /\npub\(super\) fn load_task_tag_edges_by_tag_id\b/);
  assert.doesNotMatch(rowsSource, /\nenqueue_payload_|transaction_with_behavior/, 'rows.rs should only load rows');

  const outboxSource = read('outbox.rs');
  for (const helperName of ['enqueue_copied_tag_edges']) {
    assert.match(
      outboxSource,
      new RegExp(`\\n(?:(?:pub\\(super\\)|${dbOpsVisible})\\s+)?fn\\s+${helperName}\\b`),
    );
  }
  assert.match(outboxSource, /EDGE_TASK_TAG/);
  assert.doesNotMatch(outboxSource, /\nfn\s+rename_tag_with_conn\b/, 'outbox.rs should not own rename control flow');

  const renameSource = read('rename.rs');
  assert.match(renameSource, /\npub\(crate\) struct TagRenameResult\b/);
  assert.match(renameSource, /\npub\(crate\) fn rename_tag_with_conn\b/);
  assert.match(renameSource, /transaction_with_behavior/);
  assert.match(renameSource, /log_cli_changelog/);
  assert.doesNotMatch(renameSource, /\n#\[test\]/, 'rename.rs should not keep inline tests');

  const testsSource = read('tests.rs');
  const expectedTests = [
    'rename_tag_inplace_assigns_distinct_version_to_each_task',
    'rename_tag_merge_assigns_distinct_version_to_each_moved_edge',
    'rename_tag_with_conn_merges_existing_target_and_syncs_edge_rewrites',
    'rename_tag_with_conn_renames_tag_and_syncs_affected_tasks',
  ];
  const testNames = [...testsSource.matchAll(/\nfn\s+([a-zA-Z0-9_]+)\s*\(/g)].map((match) => match[1]);
  assert.deepEqual(testNames.filter((name) => expectedTests.includes(name)).sort(), expectedTests);
  assert.equal(new Set(testNames).size, testNames.length, 'tag DB op test names should stay unique');
  assert.match(testsSource, /^use super::\*;/m);
});
