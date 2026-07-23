import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bstd::io::(?:stdout|stderr)\s*\(/;

const SCOPED_RUST_FILES = [
  'app/src-tauri/src/menu_i18n.rs',
  'app/src-tauri/src/desktop_close_policy.rs',
  'app/src-tauri/src/commands/ui/runtime_status.rs',
];

test('Tauri preference fallback diagnostics persist instead of writing stdout or stderr', () => {
  for (const relativePath of SCOPED_RUST_FILES) {
    const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.doesNotMatch(
      source,
      DIRECT_OUTPUT_PATTERN,
      `${relativePath} must use structured diagnostics instead of printing directly`,
    );
  }

  const desktopClosePolicy = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/desktop_close_policy.rs'),
    'utf8',
  );
  assert.match(desktopClosePolicy, /DESKTOP_CLOSE_POLICY_LOG_SOURCE/);
  assert.match(desktopClosePolicy, /append_desktop_close_policy_log_with_conn/);

  const menuI18n = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/menu_i18n.rs'),
    'utf8',
  );
  assert.match(menuI18n, /MENU_I18N_LOG_SOURCE/);
  assert.match(menuI18n, /append_menu_i18n_log_with_conn/);

  const runtimeStatus = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/ui/runtime_status.rs'),
    'utf8',
  );
  assert.match(runtimeStatus, /RUNTIME_STATUS_LOG_SOURCE/);
  assert.match(runtimeStatus, /append_runtime_status_log_with_conn/);
});
