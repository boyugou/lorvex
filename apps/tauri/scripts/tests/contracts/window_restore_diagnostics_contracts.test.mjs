import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_MACRO_PATTERN = /\b(?:eprintln|println|eprint|print|dbg)!\s*\(/;

function collectProductionRustFiles(relativeDir) {
  const absoluteDir = path.join(repoRoot, relativeDir);
  const files = [];
  for (const entry of fs.readdirSync(absoluteDir, { withFileTypes: true })) {
    const relativePath = path.join(relativeDir, entry.name);
    if (entry.isDirectory()) {
      files.push(...collectProductionRustFiles(relativePath));
      continue;
    }
    if (entry.isFile() && entry.name.endsWith('.rs') && entry.name !== 'tests.rs') {
      files.push(relativePath);
    }
  }
  return files.sort();
}

const WINDOW_RESTORE_FILES = [
  'app/src-tauri/src/window_restore.rs',
  ...collectProductionRustFiles('app/src-tauri/src/window_restore'),
];

test('window restore persists structured diagnostics instead of writing stdout or stderr', () => {
  for (const relativePath of WINDOW_RESTORE_FILES) {
    const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.doesNotMatch(
      source,
      DIRECT_OUTPUT_MACRO_PATTERN,
      `${relativePath} must use structured diagnostics instead of printing directly`,
    );
  }

  const diagnosticsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/window_restore/restore/diagnostics/mod.rs'),
    'utf8',
  );
  assert.match(diagnosticsSource, /WINDOW_RESTORE_LOG_SOURCE/);
  assert.match(diagnosticsSource, /append_window_restore_log_with_conn/);
});
