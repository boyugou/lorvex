import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_logs is organized as a folder-backed subsystem with ai changelog and recent logs modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/system/logs/mod.rs'), 'utf8');
  const aiChangelogSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/logs/ai_changelog.rs'),
    'utf8',
  );
  const recentLogsRootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/logs/recent_logs/mod.rs'),
    'utf8',
  );
  const errorLogsSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/logs/recent_logs/error_logs.rs'),
    'utf8',
  );
  const recentAiChangelogSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/logs/recent_logs/ai_changelog.rs'),
    'utf8',
  );
  const syncOutboxSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/logs/recent_logs/sync_outbox.rs'),
    'utf8',
  );

  assert.match(rootSource, /^mod ai_changelog;$/m);
  assert.match(rootSource, /^mod recent_logs;$/m);
  assert.match(rootSource, /^pub\(crate\) use ai_changelog::get_ai_changelog;$/m);
  assert.match(rootSource, /^pub\(crate\) use recent_logs::get_recent_logs;$/m);
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn get_ai_changelog\(|\npub\(crate\) fn get_recent_logs\(/,
    'server_logs root should remain a composition root after folder extraction',
  );

  assert.match(aiChangelogSource, /\npub\(crate\) fn get_ai_changelog\(/);
  assert.match(recentLogsRootSource, /^mod ai_changelog;$/m);
  assert.match(recentLogsRootSource, /^mod error_logs;$/m);
  assert.match(recentLogsRootSource, /^mod sync_outbox;$/m);
  assert.match(recentLogsRootSource, /\npub\(crate\) fn get_recent_logs\(/);
  assert.match(errorLogsSource, /\npub\(super\) fn append_error_log_entries\(/);
  assert.match(recentAiChangelogSource, /\npub\(super\) fn append_ai_changelog_entries\(/);
  assert.match(syncOutboxSource, /\npub\(super\) fn append_sync_outbox_entries\(/);
});
