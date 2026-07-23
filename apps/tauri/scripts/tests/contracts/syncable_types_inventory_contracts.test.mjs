import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const VERIFIER = 'scripts/verify/syncable_types_inventory.mjs';

test('syncable-types inventory verifier scans current CLI calendar production consumers', () => {
  const source = fs.readFileSync(path.join(repoRoot, VERIFIER), 'utf8');
  const expectedCliConsumers = [
    'lorvex-cli/src/commands/query/calendar.rs',
    'lorvex-cli/src/commands/mutate/calendar',
    'lorvex-cli/src/dispatch/calendar.rs',
  ];

  assert.doesNotMatch(
    source,
    /lorvex-cli\/src\/db_ops\//,
    'syncable-types verifier should not point at the removed CLI db_ops tree',
  );

  for (const rel of expectedCliConsumers) {
    assert.ok(fs.existsSync(path.join(repoRoot, rel)), `${rel} should exist`);
    assert.match(
      source,
      new RegExp(rel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      `syncable-types verifier should scan ${rel}`,
    );
  }
});
