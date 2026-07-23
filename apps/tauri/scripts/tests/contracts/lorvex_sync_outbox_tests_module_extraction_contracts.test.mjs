import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const legacyTestsPath = path.join(repoRoot, 'lorvex-sync/src/outbox/tests.rs');
const testsDir = path.join(repoRoot, 'lorvex-sync/src/outbox/tests');

test('lorvex-sync outbox tests stay split by behavior family', () => {
  assert.equal(
    fs.existsSync(legacyTestsPath),
    false,
    'outbox/tests.rs should not reappear as a mixed sync-outbox test hotspot',
  );

  const childFiles = fs
    .readdirSync(testsDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();

  assert.deepEqual(childFiles, [
    'coalesce.rs',
    'coalesce_undo_chain.rs',
    'gc_and_undo.rs',
    'hardening.rs',
    'mod.rs',
    'query_and_mutation.rs',
    'query_deletes.rs',
    'retry.rs',
  ]);

  const modSource = fs.readFileSync(path.join(testsDir, 'mod.rs'), 'utf8');
  for (const moduleName of ['coalesce', 'coalesce_undo_chain', 'gc_and_undo', 'hardening', 'query_deletes', 'query_and_mutation', 'retry']) {
    assert.match(
      modSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `outbox tests facade should register ${moduleName}.rs`,
    );
  }

  assert.match(modSource, /\nfn make_envelope\(/, 'shared envelope fixture belongs in the tests facade');
  assert.match(
    modSource,
    /\nfn make_delete_envelope\(/,
    'shared delete-envelope fixture belongs in the tests facade',
  );

  for (const fileName of childFiles) {
    const source = fs.readFileSync(path.join(testsDir, fileName), 'utf8');
    const lineCount = source.trimEnd().split('\n').length;
    const limit = fileName === 'mod.rs' ? 80 : 450;
    assert.ok(
      lineCount <= limit,
      `${fileName} should stay below ${limit} lines after module extraction, got ${lineCount}`,
    );
  }
});
