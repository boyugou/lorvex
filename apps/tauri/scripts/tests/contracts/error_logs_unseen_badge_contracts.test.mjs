import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

// Issue #2253 — contract test for the "unseen error_logs badge" on
// the Settings sidebar entry. A regression here (dropped IPC wrapper,
// removed query, mis-routed command) silently kills the badge with no
// compile-time failure, so the contract pins every surface explicitly.
test('settings sidebar badge for unseen error_logs is wired end-to-end (#2253)', () => {
  // ── Rust: the commands exist and the build script auto-registers command modules ──
  const errorLogsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/diagnostics/error_logs.rs'),
    'utf8',
  );
  assert.match(
    errorLogsSource,
    /pub fn get_unseen_error_log_count\(\)/,
    'error_logs.rs must define get_unseen_error_log_count',
  );
  assert.match(
    errorLogsSource,
    /pub fn mark_error_logs_viewed\(\)/,
    'error_logs.rs must define mark_error_logs_viewed',
  );
  assert.match(
    errorLogsSource,
    /pub\(crate\) fn read_unseen_error_log_count/,
    'error_logs.rs must expose the count helper for tests',
  );

  const diagnosticsModSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/diagnostics/mod.rs'),
    'utf8',
  );
  assert.match(
    diagnosticsModSource,
    /read_unseen_error_log_count/,
    'diagnostics/mod.rs must keep the read_unseen_error_log_count test helper reachable',
  );

  const buildScriptSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/build.rs'),
    'utf8',
  );
  assert.match(buildScriptSource, /walk_rs\(&src\.join\("commands"\), &mut files\);/);
  assert.match(errorLogsSource, /#\[tauri::command\][\s\S]*?pub fn get_unseen_error_log_count\(\)/);
  assert.match(errorLogsSource, /#\[tauri::command\][\s\S]*?pub fn mark_error_logs_viewed\(\)/);

  // ── Preference key constant ──
  const preferenceKeysSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-domain/src/preference_keys/mod.rs'),
    'utf8',
  );
  assert.match(
    preferenceKeysSource,
    /DEV_ERROR_LOGS_LAST_VIEWED_AT:\s*&str\s*=\s*"error_logs_last_viewed_at"/,
    'preference_keys.rs must define the device_state key',
  );

  // ── TypeScript IPC wrappers ──
  const ipcSettingsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/ipc/settings.ts'),
    'utf8',
  );
  assert.match(
    ipcSettingsSource,
    /export const getUnseenErrorLogCount[\s\S]*?'get_unseen_error_log_count'/,
    'ipc/settings.ts must export a typed getUnseenErrorLogCount wrapper',
  );
  assert.match(
    ipcSettingsSource,
    /export const markErrorLogsViewed[\s\S]*?'mark_error_logs_viewed'/,
    'ipc/settings.ts must export a typed markErrorLogsViewed wrapper',
  );

  // ── Frontend: sidebar controller polls + SecondaryNav badges ──
  const sidebarControllerSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/sidebar/useSidebarController.ts'),
    'utf8',
  );
  assert.match(
    sidebarControllerSource,
    /getUnseenErrorLogCount/,
    'useSidebarController.ts must consume getUnseenErrorLogCount',
  );
  assert.match(
    sidebarControllerSource,
    /unseenErrorLogCount/,
    'useSidebarController.ts must expose unseenErrorLogCount on the return value',
  );

  const secondaryNavSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/sidebar/SecondaryNav.tsx'),
    'utf8',
  );
  assert.match(
    secondaryNavSource,
    /badgeVariant="danger"/,
    'SecondaryNav.tsx must render the Settings badge in the danger variant',
  );
  assert.match(
    secondaryNavSource,
    /unseenErrorLogCount/,
    'SecondaryNav.tsx must consume the unseenErrorLogCount prop',
  );

  // ── Frontend: Data section mount fires mark_error_logs_viewed ──
  const settingsViewSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/SettingsView.tsx'),
    'utf8',
  );
  assert.match(
    settingsViewSource,
    /markErrorLogsViewed\(\)/,
    'SettingsView.tsx must call markErrorLogsViewed when the Data section activates',
  );
  assert.match(
    settingsViewSource,
    /settings-section-data/,
    'SettingsView.tsx must gate the marker on the data section',
  );

  // ── Query key is named so invalidation is targeted ──
  const queryKeyHeadsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/query/queryKeyHeads.ts'),
    'utf8',
  );
  const queryKeyFactorySource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/query/queryKeyFactory.ts'),
    'utf8',
  );
  assert.match(
    queryKeyHeadsSource,
    /unseenErrorLogCount:\s*'unseen-error-log-count'/,
    'queryKeyHeads.ts must include a named unseenErrorLogCount key head',
  );
  assert.match(
    queryKeyFactorySource,
    /unseenErrorLogCount:\s*\(\) => \[QK\.unseenErrorLogCount\] as const/,
    'queryKeyFactory.ts must expose a named unseenErrorLogCount factory',
  );

  // ── i18n: configured strict-parity locales carry the tooltip ──
  const strictParityLocales = JSON.parse(
    fs.readFileSync(path.join(repoRoot, 'app/src/locales/strict-parity.json'), 'utf8'),
  );
  assert.ok(
    Array.isArray(strictParityLocales) && strictParityLocales.length > 0,
    'strict-parity.json should define every locale that must carry complete UI copy',
  );
  for (const locale of strictParityLocales) {
    assert.equal(typeof locale, 'string', 'strict-parity locale entries must be strings');
    const data = JSON.parse(
      fs.readFileSync(path.join(repoRoot, `app/src/locales/${locale}.json`), 'utf8'),
    );
    assert.ok(
      Object.prototype.hasOwnProperty.call(data, 'nav.settingsUnseenErrors'),
      `${locale}.json must translate nav.settingsUnseenErrors`,
    );
  }
});
