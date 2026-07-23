import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { extractRustFunctionBody, readRustSources, repoRoot } from './shared.mjs';

test('command-triggered main window restore paths reuse the shared restore helper', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/commands.rs'), 'utf8');
  const source = readRustSources(
    'app/src-tauri/src/commands.rs',
    // Post-#3303 split: window_commands.rs is now a folder.
    'app/src-tauri/src/commands/ui/window_commands',
  );

  assert.doesNotMatch(
    rootSource,
    /pub use ui::window_commands::\{[\s\S]*open_main_quick_capture[\s\S]*open_main_task_detail[\s\S]*\};/,
    'commands.rs should not re-export explicit main-window intent IPC for handler registration',
  );

  const quickCaptureBody = extractRustFunctionBody(source, 'open_main_quick_capture');
  assert.match(
    quickCaptureBody,
    /focus_main_window\(&app, "open_main_quick_capture"\);/,
    'open_main_quick_capture should restore the main window through the shared helper',
  );
  assert.doesNotMatch(
    quickCaptureBody,
    /main\.show\(|main\.unminimize\(|main\.set_focus\(/,
    'open_main_quick_capture should not keep a weaker hand-rolled main-window restore path',
  );

  const taskDetailBody = extractRustFunctionBody(source, 'open_main_task_detail');
  assert.match(
    taskDetailBody,
    /focus_main_window\(&app, "open_main_task_detail"\);/,
    'open_main_task_detail should restore the main window through the shared helper',
  );
  assert.doesNotMatch(
    taskDetailBody,
    /main\.show\(|main\.unminimize\(|main\.set_focus\(/,
    'open_main_task_detail should not keep a weaker hand-rolled main-window restore path',
  );
});
