import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, readTypeScriptSources, repoRoot } from './shared.mjs';

const AUXILIARY_WINDOW_IPC_COMMANDS = [
  'hide_popover_window',
  'open_main_quick_capture',
  'open_main_task_detail',
];

test('auxiliary window IPC command names stay aligned across TS wrappers, Rust commands, and generated handler exposure', () => {
  const ipcSource = readTypeScriptSources('app/src/lib/ipc/runtime.ts');
  // Post-#3303 split: window_commands.rs became a folder-backed subsystem;
  // read the entire folder so the contract catches the IPC names wherever
  // they now live.
  const rustCommandSource = readRustSources(
    'app/src-tauri/src/commands.rs',
    'app/src-tauri/src/commands/ui/window_commands',
  );
  const tauriLibSource = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/lib.rs'), 'utf8');
  const buildScriptSource = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/build.rs'), 'utf8');

  assert.match(tauriLibSource, /commands::apply_invoke_handlers\(builder\)/);
  assert.match(buildScriptSource, /walk_rs\(&src\.join\("commands"\), &mut files\);/);

  for (const commandName of AUXILIARY_WINDOW_IPC_COMMANDS) {
    assert.match(
      ipcSource,
      new RegExp(`invoke\\('${commandName}'[\\s\\S]*?\\)`),
      `ipc.ts should invoke ${commandName}`,
    );
    assert.match(
      rustCommandSource,
      new RegExp(`#\\[tauri::command\\][\\s\\S]*?pub fn ${commandName}\\(`),
      `Rust command modules should define ${commandName} as a generated Tauri command`,
    );
  }
});
