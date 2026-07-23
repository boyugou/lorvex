import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

test('diagnostics commands are organized as a folder-backed subsystem with changelog feedback and error-log modules', () => {
  const suiteRoot = path.join(repoRoot, 'app/src-tauri/src/commands/diagnostics');
  const rootSource = fs.readFileSync(path.join(suiteRoot, 'mod.rs'), 'utf8');

  for (const fileName of ['changelog.rs', 'error_logs.rs']) {
    assert.ok(
      fs.existsSync(path.join(suiteRoot, fileName)),
      `diagnostics should include ${fileName}`,
    );
  }

  assert.match(rootSource, rustModuleDeclarationPattern('changelog'));
  assert.match(rootSource, rustModuleDeclarationPattern('error_logs'));
  assert.equal(
    hasRustUseReexport(rootSource, {
      modulePath: 'changelog',
      symbols: ['get_changelog'],
    }),
    true,
    'diagnostics/mod.rs should re-export get_changelog from changelog.rs',
  );
  assert.equal(
    hasRustUseReexport(rootSource, {
      modulePath: 'error_logs',
      symbols: ['append_error_log', 'clear_error_logs', 'get_error_logs'],
    }),
    true,
    'diagnostics/mod.rs should re-export error log commands from error_logs.rs',
  );
  // Renderer-facing feedback IPC commands (clear/export/get_feedback_entries)
  // were deleted; the diagnostics bundle now ships feedback through the
  // bundle.rs entrypoint instead.
  assert.equal(
    hasRustUseReexport(rootSource, {
      modulePath: 'error_logs',
      symbols: ['append_error_log_internal'],
      visibility: 'crate',
    }),
    true,
    'diagnostics/mod.rs should keep append_error_log_internal re-exported for crate-local use',
  );
});
