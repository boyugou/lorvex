import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('task lifecycle runtime lives in a folder-backed subsystem instead of one flat hotspot file', () => {
  const lifecycleDir = path.join(repoRoot, 'mcp-server/src/tasks/lifecycle');

  assert.ok(
    fs.existsSync(lifecycleDir),
    'server_task_lifecycle/ should exist as a dedicated subsystem directory',
  );
  // `recurrence` is now folder-backed (`recurrence/mod.rs` + tests).
  assert.ok(
    fs.existsSync(path.join(lifecycleDir, 'mod.rs')),
    'server_task_lifecycle/mod.rs should exist',
  );
  assert.ok(
    fs.existsSync(path.join(lifecycleDir, 'recurrence/mod.rs')),
    'server_task_lifecycle/recurrence/mod.rs should exist',
  );
  assert.ok(fs.existsSync(path.join(lifecycleDir, 'writes')), 'server_task_lifecycle/writes/ should exist');
  // `tests` was promoted from a single tests.rs file to a folder of focused
  // per-domain test modules; the production write-handler files still live
  // as flat siblings.
  for (const relativePath of ['mod.rs', 'set_task_ai_notes.rs', 'cancel.rs', 'complete.rs', 'permanent_delete.rs']) {
    assert.ok(
      fs.existsSync(path.join(lifecycleDir, 'writes', relativePath)),
      `server_task_lifecycle/writes/${relativePath} should exist`,
    );
  }
  assert.ok(
    fs.existsSync(path.join(lifecycleDir, 'writes/tests/mod.rs')),
    'server_task_lifecycle/writes/tests/mod.rs should exist (tests promoted to folder)',
  );
  assert.ok(
    !fs.existsSync(path.join(lifecycleDir, 'writes.rs')),
    'the flat server_task_lifecycle/writes.rs hotspot should be removed after subtree extraction',
  );
  assert.ok(
    !fs.existsSync(path.join(repoRoot, 'mcp-server/src/tasks/lifecycle.rs')),
    'the legacy flat server_task_lifecycle.rs hotspot should be removed after the subsystem split',
  );
});
