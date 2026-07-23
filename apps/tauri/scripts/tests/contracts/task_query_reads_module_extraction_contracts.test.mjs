import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('generic task read commands live in task_queries instead of task_commands', () => {
  const commandsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );
  const taskCommandsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/mod.rs'),
    'utf8',
  );
  // Post-split: tasks/queries.rs became tasks/queries/{mod,tests}.rs.
  const taskQueriesSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/queries/mod.rs'),
    'utf8',
  );

  assert.doesNotMatch(
    commandsSource,
    /^pub use tasks::queries::\{[\s\S]*get_task[\s\S]*search_tasks[\s\S]*\};$/m,
    'commands.rs should not re-export generic task read IPC for handler registration',
  );

  for (const fnName of ['get_task', 'search_tasks']) {
    assert.match(
      taskQueriesSource,
      new RegExp(`\\n#\\[tauri::command\\]\\npub fn ${fnName}\\(`),
      `task_queries.rs should own ${fnName}`,
    );
    assert.doesNotMatch(
      taskCommandsSource,
      new RegExp(`\\n#\\[tauri::command\\]\\npub fn ${fnName}\\(`),
      `task_commands.rs should not keep ${fnName} after the read/query extraction`,
    );
  }
});
