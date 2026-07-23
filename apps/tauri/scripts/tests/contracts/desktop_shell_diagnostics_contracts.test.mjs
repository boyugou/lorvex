import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bstd::io::(?:stdout|stderr)\s*\(/;

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

test('desktop shell persists diagnostics instead of writing stdout or stderr', () => {
  for (const relativePath of collectProductionRustFiles('app/src-tauri/src/desktop_shell')) {
    const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.doesNotMatch(
      source,
      DIRECT_OUTPUT_PATTERN,
      `${relativePath} must use structured diagnostics instead of printing directly`,
    );
  }

  const shellSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/desktop_shell/mod.rs'),
    'utf8',
  );
  assert.match(shellSource, /DESKTOP_SHELL_LOG_SOURCE/);
  assert.match(shellSource, /append_desktop_shell_log_with_conn/);
});
