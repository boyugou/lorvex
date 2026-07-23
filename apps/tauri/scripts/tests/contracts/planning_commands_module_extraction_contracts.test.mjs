import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

test('commands root delegates planning commands to a dedicated module', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );

  assert.match(
    source,
    rustModuleDeclarationPattern('planning'),
    'commands.rs should register a dedicated planning module tree',
  );
  assert.doesNotMatch(
    source,
    /^pub use planning::\{[\s\S]*get_current_focus[\s\S]*get_focus_schedule[\s\S]*reorder_current_focus_open_tasks[\s\S]*\};$/m,
    'commands.rs should not re-export planning IPC commands for handler registration',
  );
  assert.doesNotMatch(
    source,
    /\n#\[tauri::command\]\npub fn get_current_focus\(|\n#\[tauri::command\]\npub fn reorder_current_focus_open_tasks\(|\n#\[tauri::command\]\npub fn get_focus_schedule\(/,
    'commands.rs should not keep inline planning command implementations after extraction',
  );
});
