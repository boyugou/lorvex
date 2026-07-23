import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const trackedSchemaPath = 'app/src-tauri/gen/schemas/desktop-schema.json';

test('tracked Tauri schemas are not hidden by ignore rules', () => {
  const tracked = spawnSync('git', ['ls-files', trackedSchemaPath], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
  assert.equal(tracked.status, 0);
  assert.equal(tracked.stdout.trim(), trackedSchemaPath);

  const ignored = spawnSync(
    'git',
    ['check-ignore', '-v', '--no-index', trackedSchemaPath],
    {
      cwd: repoRoot,
      encoding: 'utf8',
    },
  );
  assert.notEqual(
    ignored.status,
    0,
    `tracked schema should not match an ignore rule:\n${ignored.stdout}${ignored.stderr}`,
  );
});
