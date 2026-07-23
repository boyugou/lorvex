import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('AppError IPC boundary persists structured diagnostics instead of stderr', () => {
  const source = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/error.rs'), 'utf8');
  const boundarySource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/error/boundary.rs'),
    'utf8',
  );
  const diagnosticsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/diagnostics/error_logs.rs'),
    'utf8',
  );
  const dbSource = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/db/connection.rs'), 'utf8');
  const storePoolSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-store/src/connection_pool.rs'),
    'utf8',
  );
  const fromImpl = boundarySource.match(/impl From<AppError> for String \{[\s\S]*?\n\}/);
  const tryAppendImpl = diagnosticsSource.match(
    /pub\(crate\) fn try_append_error_log_best_effort\([\s\S]*?\n\}/,
  );

  assert.match(source, /^mod boundary;$/m);
  assert.ok(fromImpl, 'AppError -> String boundary must remain explicit');
  assert.ok(tryAppendImpl, 'AppError boundary diagnostics must use a nonblocking writer helper');
  assert.doesNotMatch(
    fromImpl[0],
    /eprintln!\s*\(/,
    'AppError -> String boundary must not write stderr directly in packaged app builds',
  );
  assert.match(fromImpl[0], /append_app_error_boundary_log_best_effort/);
  assert.match(boundarySource, /try_append_error_log_best_effort/);
  assert.match(tryAppendImpl[0], /try_get_conn/);
  assert.doesNotMatch(
    tryAppendImpl[0],
    /crate::db::get_conn\s*\(/,
    'AppError boundary diagnostics must not block on the writer mutex while returning IPC errors',
  );
  assert.match(dbSource, /try_get_conn[\s\S]*try_writer_result/);
  assert.match(storePoolSource, /try_writer_result[\s\S]*try_lock\(\)/);
  assert.match(storePoolSource, /TryLockError::WouldBlock\)\s*=>\s*Ok\(None\)/);
  assert.match(boundarySource, /app\.command_error\.boundary/);
});
