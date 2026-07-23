import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('HLC local-history seed failures use structured diagnostics', () => {
  const source = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/hlc.rs'), 'utf8');
  const seedFailureBlock = source.match(
    /if let Err\(err\) =[\s\S]*?seed_hlc_state_from_local_history\([\s\S]*?\)\s*\{[\s\S]*?\n\s*\}/,
  );

  assert.ok(seedFailureBlock, 'init_hlc must handle local-history seed failures explicitly');
  assert.doesNotMatch(
    seedFailureBlock[0],
    /eprintln!\s*\(/,
    'HLC seed failures must not be stderr-only in packaged app builds',
  );
  assert.match(source, /hlc\.seed\.local_history_failure/);
});
