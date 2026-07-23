import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const facadePath = path.join(repoRoot, 'lorvex-sync/src/apply/tag.rs');
const tagDir = path.join(repoRoot, 'lorvex-sync/src/apply/tag');

function read(relativePath) {
  return fs.readFileSync(path.join(tagDir, relativePath), 'utf8');
}

test('lorvex-sync tag apply handler stays split by responsibility', () => {
  const facadeSource = fs.readFileSync(facadePath, 'utf8');
  assert.ok(fs.existsSync(tagDir), 'apply/tag/ should contain the extracted tag modules');

  const moduleFiles = fs
    .readdirSync(tagDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, ['handlers.rs', 'merge.rs', 'payload.rs', 'tests.rs']);

  for (const moduleName of ['handlers', 'merge', 'payload']) {
    assert.match(
      facadeSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `tag.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(facadeSource, /^#\[cfg\(test\)\]\nmod tests;$/m);
  assert.match(
    facadeSource,
    /pub\(crate\) use handlers::\{apply_tag_delete, apply_tag_upsert\};/,
    'tag.rs should re-export only the dispatch entry points',
  );

  const facadeLineCount = facadeSource.trimEnd().split('\n').length;
  assert.ok(facadeLineCount <= 40, `tag.rs should stay a thin facade, got ${facadeLineCount} lines`);
  assert.doesNotMatch(
    facadeSource,
    /\n#\[test\]|\nfn\s+\w+|\nstruct\s+\w+|\nimpl\s+/,
    'tag.rs should not keep implementation or tests inline',
  );

  const payloadSource = read('payload.rs');
  for (const helperName of [
    'str_field',
    'optional_str_preserving_empty',
    'nullable_str_or_clear',
    'required_str',
  ]) {
    assert.match(
      payloadSource,
      new RegExp(`(?:^|\\n)(?:#\\[inline\\]\\n)?(?:pub\\(super\\)\\s+)?(?:const\\s+)?fn\\s+${helperName}\\b`),
      `payload.rs should own ${helperName}`,
    );
  }

  const handlersSource = read('handlers.rs');
  assert.match(handlersSource, /\npub\(crate\) fn apply_tag_upsert\b/);
  assert.match(handlersSource, /\npub\(crate\) fn apply_tag_delete\b/);
  assert.doesNotMatch(
    handlersSource,
    /\nfn\s+merge_duplicate_tags\b|\n#\[test\]/,
    'handlers.rs should not own merge internals or tests',
  );

  const mergeSource = read('merge.rs');
  assert.match(mergeSource, /\npub\(super\) fn merge_duplicate_tags\b/);
  // Note: the historical `read_divergent_tag_fields` helper was inlined back into
  // `merge_duplicate_tags` after the conflict-detection logic was simplified to
  // a single SELECT. The merge module no longer carries a divergence helper
  // function; the conflict-logging step is part of the main merge flow.
  assert.doesNotMatch(
    mergeSource,
    /\npub\(crate\) fn apply_tag_upsert\b|\npub\(crate\) fn apply_tag_delete\b|\n#\[test\]/,
    'merge.rs should not own apply entry points or tests',
  );

  const testsSource = read('tests.rs');
  const expectedTests = [
    'upsert_inserts_new_tag',
    'upsert_rederives_lookup_key_from_display_name_ignoring_payload_value',
    'upsert_updates_when_version_is_newer',
    'upsert_skips_when_version_is_older',
    'delete_removes_existing_tag',
    'delete_is_idempotent_for_missing_tag',
    'stale_delete_envelope_is_refused_by_in_row_lww_guard',
    'merge_keeps_smaller_id_and_tombstones_loser',
    'merge_repoints_task_tags_from_loser_to_winner',
    'no_merge_when_lookup_keys_differ',
    'stale_envelope_does_not_trigger_merge',
    'merge_stamps_winner_tag_version_at_merge_version',
    'merge_observes_local_event_with_merge_version',
    'merge_reports_clear_error_when_no_canonical_hlc_successor_exists',
    'merge_logs_conflict_when_loser_display_name_or_color_differs',
    'merge_does_not_log_conflict_when_loser_fields_match_winner',
  ];
  const testNames = [...testsSource.matchAll(/\nfn\s+([a-zA-Z0-9_]+)\s*\(/g)].map((match) => match[1]);
  assert.deepEqual(testNames.filter((name) => expectedTests.includes(name)).sort(), expectedTests.toSorted());
  assert.equal(new Set(testNames).size, testNames.length, 'tag apply test names should stay unique');
  assert.match(testsSource, /^use super::\*;/m);
  assert.match(testsSource, /^use rusqlite::params;/m);
});
