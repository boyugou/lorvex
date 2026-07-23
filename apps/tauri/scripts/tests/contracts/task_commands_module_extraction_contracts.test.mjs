import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

test('commands root delegates task mutation commands to a dedicated module', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );

  assert.match(
    source,
    rustModuleDeclarationPattern('tasks'),
    'commands.rs should register a dedicated task_commands leaf module',
  );
  assert.doesNotMatch(
    source,
    /\npub use tasks::\{[\s\S]*(?:quick_capture|complete_task|update_task|defer_task|cancel_task)[\s\S]*\};/,
    'commands.rs should not re-export task IPC commands for handler registration',
  );
  assert.doesNotMatch(
    source,
    /\n#\[tauri::command\]\npub fn quick_capture\(|\n#\[tauri::command\]\npub fn complete_task\(|\n#\[tauri::command\]\npub fn get_task\(|\n#\[tauri::command\]\npub fn get_task_attribution\(|\n#\[tauri::command\]\npub fn search_tasks\(|\n#\[tauri::command\]\npub fn update_task\(|\n#\[tauri::command\]\npub fn defer_task\(|\n#\[tauri::command\]\npub fn defer_task_until\(|\n#\[tauri::command\]\npub fn reopen_task\(|\n#\[tauri::command\]\npub fn cancel_task\(|\n#\[tauri::command\]\npub fn permanent_delete_task\(|\n#\[tauri::command\]\npub fn reset_task_deferral\(/,
    'commands.rs should not keep inline task command implementations after extraction',
  );
});
