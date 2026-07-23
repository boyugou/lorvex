import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

import { hasRustUseReexport } from './shared.mjs';

const repoRoot = path.resolve(import.meta.dirname, '..', '..', '..');
const commandsPath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands.rs');

test('commands root delegates desktop window and deep-link intent commands to a dedicated module', () => {
  const source = fs.readFileSync(commandsPath, 'utf8');

  assert.match(source, /^pub\(crate\) mod ui;$/m);

  assert.equal(
    hasRustUseReexport(source, {
      modulePath: 'ui::window_commands',
      symbols: ['hide_popover_window'],
      visibility: 'crate',
    }),
    true,
    'commands.rs should re-export only desktop shell orchestration helpers',
  );

  for (const snippet of [
    'pub fn open_main_quick_capture(',
    'pub fn set_native_window_effects(',
    'pub fn set_tray_icon_visibility(',
    'pub fn hide_popover_window(',
    'pub fn open_main_task_detail(',
    'pub fn consume_pending_deep_link(',
    'pub fn acknowledge_pending_deep_link(',
  ]) {
    assert.equal(
      source.includes(snippet),
      false,
      `commands.rs should no longer inline desktop window command snippet: ${snippet}`,
    );
  }
});
