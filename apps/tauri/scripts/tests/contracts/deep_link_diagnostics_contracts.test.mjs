import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bstd::io::(?:stdout|stderr)\s*\(/;

const SCOPED_RUST_FILES = [
  'app/src-tauri/src/deep_link/mod.rs',
  'app/src-tauri/src/deep_link/queue.rs',
  'app/src-tauri/src/plugins.rs',
  'app/src-tauri/src/runtime_events.rs',
];

const EXPECTED_DEEP_LINK_DIAGNOSTICS = [
  {
    relativePath: 'app/src-tauri/src/deep_link/queue.rs',
    sourceSuffix: 'pending_ack',
    message: 'ignored malformed pending deep link payload',
  },
  {
    relativePath: 'app/src-tauri/src/plugins.rs',
    sourceSuffix: 'open_task_argv',
    message: 'ignored malformed --open-task argument',
  },
  {
    relativePath: 'app/src-tauri/src/runtime_events.rs',
    sourceSuffix: 'opened_url',
    message: 'ignored malformed deep link URL',
  },
];

test('deep-link input diagnostics persist instead of writing stdout or stderr', () => {
  for (const relativePath of SCOPED_RUST_FILES) {
    const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.doesNotMatch(
      source,
      DIRECT_OUTPUT_PATTERN,
      `${relativePath} must use structured diagnostics instead of printing directly`,
    );
  }

  const deepLinkRoot = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/deep_link/mod.rs'),
    'utf8',
  );
  assert.match(deepLinkRoot, /DEEP_LINK_LOG_SOURCE/);
  assert.match(deepLinkRoot, /append_deep_link_log_with_conn/);

  for (const { relativePath, sourceSuffix, message } of EXPECTED_DEEP_LINK_DIAGNOSTICS) {
    const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.match(
      source,
      new RegExp(`append_deep_link_log\\(\\s*"warn",\\s*"${sourceSuffix}"`, 's'),
      `${relativePath} must persist malformed input diagnostics with deep_link.${sourceSuffix}`,
    );
    assert.match(
      source,
      new RegExp(`"${message.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"`),
      `${relativePath} must keep a stable diagnostic message for deep_link.${sourceSuffix}`,
    );
  }
});
