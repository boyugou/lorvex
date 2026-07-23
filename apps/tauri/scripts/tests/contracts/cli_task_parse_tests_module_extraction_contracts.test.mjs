import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const facadePath = path.join(repoRoot, 'lorvex-cli/src/cli/tests/task.rs');
const taskDir = path.join(repoRoot, 'lorvex-cli/src/cli/tests/task');

function read(relativePath) {
  return fs.readFileSync(path.join(taskDir, relativePath), 'utf8');
}

function testNames(source) {
  return [...source.matchAll(/\n#\[test\]\s*\nfn\s+([a-zA-Z0-9_]+)\s*\(/g)].map((match) => match[1]);
}

function assertOwnsTests(source, expectedNames, label) {
  const names = testNames(source);
  assert.deepEqual(
    names.filter((name) => expectedNames.includes(name)).sort(),
    expectedNames.toSorted(),
    `${label} should own its expected test functions`,
  );
  assert.equal(new Set(names).size, names.length, `${label} test names should stay unique`);
}

test('CLI task parse tests stay split by command responsibility', () => {
  const facadeSource = fs.readFileSync(facadePath, 'utf8');
  assert.ok(fs.existsSync(taskDir), 'cli/tests/task/ should contain the extracted task parse test modules');

  const moduleFiles = fs
    .readdirSync(taskDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, ['mutation.rs', 'query.rs', 'validation.rs']);

  for (const moduleName of ['mutation', 'query', 'validation']) {
    assert.match(
      facadeSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `task.rs should register ${moduleName}.rs`,
    );
  }

  const facadeLineCount = facadeSource.trimEnd().split('\n').length;
  assert.ok(facadeLineCount <= 12, `task.rs should stay a thin facade, got ${facadeLineCount} lines`);
  assert.doesNotMatch(
    facadeSource,
    /\n#\[test\]|\nfn\s+\w+|\nstruct\s+\w+|\nimpl\s+/,
    'task.rs should not keep tests inline',
  );

  assertOwnsTests(read('query.rs'), [
    'parse_dependency_graph_query',
    'parse_tasks_filters',
    'parse_today_overdue_upcoming',
  ], 'query.rs');

  assertOwnsTests(read('mutation.rs'), [
    'parse_cancel_preserves_series_tristate',
    'parse_capture_complete_reopen',
    'parse_defer_all_fields',
    'parse_trash_lifecycle_tree',
    'parse_update_task_fields_and_clears',
    'task_update_supports_status_and_raw_input_flags',
  ], 'mutation.rs');

  assertOwnsTests(read('validation.rs'), [
    'capture_structured_fields_validate_at_parse_time',
    'list_id_args_accept_inbox_sentinel',
    'uuid_id_args_reject_non_uuid_strings_at_parse_time',
  ], 'validation.rs');
});
