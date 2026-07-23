import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('window_restore is organized as a folder-backed subsystem with restore and session modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/window_restore.rs'),
    'utf8',
  );
  const restoreRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/window_restore/restore/mod.rs'),
    'utf8',
  );
  const sessionRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/window_restore/session/mod.rs'),
    'utf8',
  );
  const sessionRuntimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/window_restore/session/runtime.rs'),
    'utf8',
  );
  const sessionStateSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/window_restore/session/state.rs'),
    'utf8',
  );
  const diagnosticsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/window_restore/restore/diagnostics/mod.rs'),
    'utf8',
  );
  const mainWindowSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/window_restore/restore/main_window.rs'),
    'utf8',
  );

  assert.match(rootSource, /^mod restore;$/m);
  assert.match(rootSource, /^mod session;$/m);
  assert.match(rootSource, /^pub\(crate\) use restore::restore_main_window_direct;$/m);
  assert.match(
    rootSource,
    /^pub\(crate\) use session::\{focus_main_window, focus_primary_window\};$/m,
  );
  assert.doesNotMatch(
    rootSource,
    /\nfn focus_window\(|\npub\(crate\) fn focus_primary_window\(|\npub\(crate\) fn restore_main_window_direct\(/,
    'window_restore root should stay a composition root after folder extraction',
  );
  assert.match(restoreRootSource, /^mod diagnostics;$/m);
  assert.match(restoreRootSource, /^mod main_window;$/m);
  assert.match(sessionRootSource, /^mod runtime;$/m);
  assert.match(sessionRootSource, /^mod state;$/m);
  assert.match(
    sessionRootSource,
    /^pub\(crate\) use runtime::\{focus_main_window, focus_primary_window\};$/m,
  );
  assert.match(
    restoreRootSource,
    /^pub\(crate\) use main_window::restore_main_window_direct;$/m,
  );
  assert.doesNotMatch(
    restoreRootSource,
    /\nfn hide_popover_for_window_restore\(|\npub\(crate\) fn restore_main_window_direct\(/,
    'restore/mod.rs should stay a composition root after the internal split',
  );
  assert.match(
    diagnosticsSource,
    /\npub\(in crate::window_restore\) fn append_window_restore_log\(/,
  );
  assert.match(mainWindowSource, /\npub\(crate\) fn restore_main_window_direct\(/);
  assert.match(mainWindowSource, /\nfn hide_popover_for_window_restore\(/);
  assert.match(sessionRuntimeSource, /\npub\(crate\) fn focus_primary_window\(/);
  assert.match(sessionRuntimeSource, /\nfn focus_window\(/);
  assert.match(
    sessionStateSource,
    /\nstatic WINDOW_RESTORE_IN_FLIGHT: AtomicBool = AtomicBool::new\(false\);/,
  );
  assert.match(
    sessionStateSource,
    /\npub\(super\) fn claim_window_restore_in_flight\(\) -> bool \{/,
  );
});
