import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bstd::io::(?:stdout|stderr)\s*\(/;

// `notification_actions` was historically a single ~870-line file; it now
// splits into `notification_actions/{mod,macos,windows,fallback}.rs`. Read
// every production `.rs` file in the directory and concatenate before scanning
// so the contract continues to enforce diagnostic discipline across the whole
// platform module after the refactor — without this, a regression could land
// `println!(...)` in `windows.rs` and slip past a verifier that only inspected
// `mod.rs`.
const NOTIFICATION_ACTIONS_DIR = 'app/src-tauri/src/platform/notification_actions';
// Post-#3303 split: bootstrap.rs became a folder.
const BOOTSTRAP_PATH = 'app/src-tauri/src/bootstrap';

function readNotificationActionsSource() {
  // Post-#3303: macOS surface itself splits into macos/{actions,delegate,mod}.rs.
  // Walk the whole subtree (excluding tests.rs).
  const dirAbs = path.join(repoRoot, NOTIFICATION_ACTIONS_DIR);
  const out = [];
  function walk(absDir) {
    for (const entry of fs.readdirSync(absDir, { withFileTypes: true })) {
      const childAbs = path.join(absDir, entry.name);
      if (entry.isDirectory()) {
        walk(childAbs);
      } else if (entry.isFile() && entry.name.endsWith('.rs') && entry.name !== 'tests.rs') {
        out.push(`// === ${path.relative(repoRoot, childAbs)} ===\n${fs.readFileSync(childAbs, 'utf8')}`);
      }
    }
  }
  walk(dirAbs);
  return out.join('\n');
}

test('notification action diagnostics persist instead of writing stdout or stderr', () => {
  const source = readNotificationActionsSource();
  const bootstrapSource = readRustSources(BOOTSTRAP_PATH);

  assert.doesNotMatch(
    source,
    DIRECT_OUTPUT_PATTERN,
    `${NOTIFICATION_ACTIONS_DIR} must use structured diagnostics instead of direct output`,
  );
  assert.match(source, /log_notification_panic/);
  assert.match(source, /catch_unwind_without_default_panic_hook/);
  assert.doesNotMatch(source, /std::panic::catch_unwind/);
  assert.match(source, /append_error_log_internal/);
  assert.match(source, /platform\.notification_actions/);
  assert.match(bootstrapSource, /SUPPRESS_DEFAULT_PANIC_HOOK/);
  assert.match(bootstrapSource, /catch_unwind_without_default_panic_hook/);
  assert.match(bootstrapSource, /let\s+suppress_default\s*=\s*SUPPRESS_DEFAULT_PANIC_HOOK/);
  assert.match(bootstrapSource, /if\s+!suppress_default/);
  assert.match(bootstrapSource, /default_hook\(info\)/);
});
