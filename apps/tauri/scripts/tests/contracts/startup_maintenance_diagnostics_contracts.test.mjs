import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('shared sync startup maintenance returns structured diagnostics instead of writing stdout or stderr', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'lorvex-sync/src/startup_maintenance/mod.rs'),
    'utf8',
  );

  assert.doesNotMatch(
    source,
    /\b(?:eprintln|println|eprint|print|dbg)!\s*\(/,
    'shared startup maintenance must return StartupMaintenanceWarning rows for callers to persist instead of printing directly',
  );
  assert.match(source, /struct StartupMaintenanceWarning \{/);
  assert.match(source, /pub fn persist_startup_maintenance_warnings\(/);
});
