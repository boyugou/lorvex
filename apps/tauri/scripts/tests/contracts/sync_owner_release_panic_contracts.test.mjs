import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const PRODUCTION_SYNC_OWNER_CALLS = [
  'app/src-tauri/src/commands/sync/filesystem_bridge/runtime/command.rs',
];

test('production sync-owner guards install structured release panic hooks', () => {
  for (const sourcePath of PRODUCTION_SYNC_OWNER_CALLS) {
    const source = fs.readFileSync(path.join(repoRoot, sourcePath), 'utf8');
    const call = source.match(
      /try_acquire_sync_owner_with_guard_now\([\s\S]*?\n\s*\)\n\s*\.map_err/,
    );

    assert.ok(call, `${sourcePath} must acquire sync-owner through the runtime guard`);

    assert.doesNotMatch(
      call[0],
      /,\s*None\s*,?\s*\n\s*\)\n\s*\.map_err/,
      `${sourcePath} must not opt into the runtime sync-owner stderr fallback hook`,
    );
  }

  assert.equal(
    fs.existsSync(path.join(repoRoot, 'app/src-tauri/src/commands/sync/cloudkit/runtime/command.rs')),
    false,
    'retired Remote provider sync runtime must not be required for release panic-hook coverage',
  );
});
