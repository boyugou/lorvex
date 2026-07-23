import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

test('task_commands is organized as a folder-backed subsystem instead of a single flat hotspot', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/mod.rs'),
    'utf8',
  );

  assert.match(rootSource, rustModuleDeclarationPattern('capture'));
  assert.match(rootSource, rustModuleDeclarationPattern('completion'));
  assert.match(rootSource, rustModuleDeclarationPattern('lifecycle'));
  assert.match(rootSource, rustModuleDeclarationPattern('updates'));
  for (const fnName of ['quick_capture', 'duplicate_task']) {
    assert.match(
      rootSource,
      new RegExp(`pub use capture::\\{[\\s\\S]*\\b${fnName}\\b`, 'm'),
      `task_commands root should re-export ${fnName} from capture.rs`,
    );
  }
  assert.match(
    rootSource,
    /^pub use completion::complete_task;$/m,
    'task_commands root should delegate completion to completion.rs',
  );
  assert.match(
    rootSource,
    /^pub use lifecycle::\{[\s\S]*\};$/m,
    'task_commands root should re-export lifecycle commands from lifecycle.rs',
  );
  for (const fnName of [
    'defer_task',
    'defer_task_until',
    'reopen_task',
    'cancel_task',
    'permanent_delete_task',
    'reset_task_deferral',
    'restore_task_deferral',
  ]) {
    assert.match(
      rootSource,
      new RegExp(`pub use lifecycle::\\{[\\s\\S]*\\b${fnName}\\b`, 'm'),
      `task_commands root should re-export ${fnName} from lifecycle.rs`,
    );
  }
  assert.match(
    rootSource,
    /^pub use updates::\{[\s\S]*update_task[\s\S]*\};$/m,
    'task_commands root should delegate updates to updates.rs',
  );
  assert.doesNotMatch(
    rootSource,
    /\n#\[tauri::command\]\npub fn quick_capture\(|\n#\[tauri::command\]\npub fn complete_task\(|\n#\[tauri::command\]\npub fn update_task\(|\n#\[tauri::command\]\npub fn defer_task\(|\n#\[tauri::command\]\npub fn defer_task_until\(|\n#\[tauri::command\]\npub fn reopen_task\(|\n#\[tauri::command\]\npub fn cancel_task\(|\n#\[tauri::command\]\npub fn permanent_delete_task\(|\n#\[tauri::command\]\npub fn reset_task_deferral\(|\n#\[tauri::command\]\npub fn restore_task_deferral\(/,
    'task_commands root should remain a composition layer after folder extraction',
  );

  const captureSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/capture/mod.rs'),
    'utf8',
  );
  const completionSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/completion/mod.rs'),
    'utf8',
  );
  const lifecycleRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/lifecycle/mod.rs'),
    'utf8',
  );
  const lifecycleSource = readRustSources(
    'app/src-tauri/src/commands/tasks/lifecycle',
  );
  const updatesSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/updates.rs'),
    'utf8',
  );
  const updateCommandSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/updates/command.rs'),
    'utf8',
  );

  for (const fnName of ['quick_capture', 'duplicate_task']) {
    assert.match(
      captureSource,
      new RegExp(`\\n#\\[tauri::command\\]\\npub fn ${fnName}\\(`),
      `capture.rs should own ${fnName}`,
    );
  }
  assert.match(completionSource, /\n#\[tauri::command\]\npub fn complete_task\(/);
  for (const moduleName of ['deferral', 'removal', 'reopen']) {
    assert.match(
      lifecycleRootSource,
      rustModuleDeclarationPattern(moduleName),
      `lifecycle root should register ${moduleName}.rs`,
    );
  }
  assert.match(
    lifecycleRootSource,
    /^pub use deferral::\{defer_task, defer_task_until, reset_task_deferral, restore_task_deferral\};$/m,
    'lifecycle root should re-export deferral commands from deferral.rs',
  );
  assert.match(
    lifecycleRootSource,
    /^pub use removal::\{cancel_task, permanent_delete_task, purge_cancelled_tasks\};$/m,
    'lifecycle root should re-export removal commands from removal.rs',
  );
  assert.match(
    lifecycleRootSource,
    /^pub use reopen::reopen_task;$/m,
    'lifecycle root should re-export reopen_task from reopen.rs',
  );
  assert.doesNotMatch(
    lifecycleRootSource,
    /\n#\[tauri::command\]\npub fn defer_task\(|\n#\[tauri::command\]\npub fn defer_task_until\(|\n#\[tauri::command\]\npub fn reopen_task\(|\n#\[tauri::command\]\npub fn cancel_task\(|\n#\[tauri::command\]\npub fn permanent_delete_task\(|\n#\[tauri::command\]\npub fn reset_task_deferral\(|\n#\[tauri::command\]\npub fn restore_task_deferral\(/,
    'lifecycle/mod.rs should remain a composition root after nested folder extraction',
  );

  for (const fnName of [
    'defer_task',
    'defer_task_until',
    'reopen_task',
    'cancel_task',
    'permanent_delete_task',
    'reset_task_deferral',
    'restore_task_deferral',
  ]) {
    assert.match(
      lifecycleSource,
      new RegExp(`\\n#\\[tauri::command\\]\\npub fn ${fnName}\\(`),
      `lifecycle.rs should own ${fnName}`,
    );
  }
  assert.match(
    updatesSource,
    /^pub use command::update_task;$/m,
    'updates.rs should re-export update_task from updates/command.rs',
  );
  assert.match(updateCommandSource, /\n#\[tauri::command\]\npub fn update_task\(/);
});
