import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, readTypeScriptSources, repoRoot } from './shared.mjs';

test('Remote provider sync state only uses the structured pull cursor and not the legacy timestamp key', () => {
  const fullSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );
  const source = fullSource.split('\n#[cfg(test)]\nmod tests {')[0] ?? fullSource;

  assert.doesNotMatch(
    source,
    /SYNC_STATE_CLOUDKIT_LAST_PULL_KEY_LEGACY|const\s+SYNC_STATE_CLOUDKIT_LAST_PULL_[A-Z_]+:\s*&str\s*=\s*"cloudkit_last_pull_updated_at";/,
    'commands.rs should not keep a legacy Remote provider timestamp-only pull cursor constant',
  );
  assert.doesNotMatch(
    source,
    /Legacy fallback: old baseline only tracked updated_at\./,
    'load_cloudkit_pull_cursor should not keep the legacy timestamp-only fallback path',
  );
});

test('feedback log filtering uses structured feedback markers instead of summary-prefix heuristics', () => {
  // The renderer-facing feedback IPC commands and the shared
  // FEEDBACK_WHERE_CLAUSE were deleted entirely once feedback rows moved
  // through the diagnostics bundle. The structural intent (no
  // summary-prefix heuristics) is preserved by checking that the legacy
  // pattern is gone from every Rust source, mirroring the pattern in
  // sibling "no compatibility shims" assertions.
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );
  const sharedSource = readRustSources(
    'app/src-tauri/src/commands/shared/mod.rs',
    'app/src-tauri/src/commands/shared',
  );
  const diagnosticsSource = readRustSources(
    'app/src-tauri/src/commands/diagnostics',
  );
  const source = `${rootSource}\n${sharedSource}\n${diagnosticsSource}`;
  assert.doesNotMatch(source, /feedback_filters_match_only_structured_feedback_rows/);
});

test('sync apply only accepts canonical array payloads and updated_at timestamps for day-scoped entities', () => {
  const source = readRustSources(
    'app/src-tauri/src/commands/sync/runtime/apply',
  );

  assert.doesNotMatch(
    source,
    /Some\(serde_json::Value::String\(s\)\)\s*=>\s*\{\s*serde_json::from_str::<Vec<String>>\(s\)/s,
    'current_focus sync apply should not preserve stringified task_ids compatibility parsing',
  );
  assert.doesNotMatch(
    source,
    /backward compat with different payload shapes/i,
    'daily_review sync apply should not keep backward-compat payload-shape handling comments',
  );
  assert.doesNotMatch(
    source,
    /\.or_else\(\|\| obj\.get\("modified_at"\)\)|\.or_else\(\|\| value\.get\("modified_at"\)\)/,
    'sync timestamp resolution should not preserve modified_at compatibility fallbacks',
  );
});

test('focus schedule payloads and snapshots use canonical arrays instead of stringified JSON', () => {
  const source = readRustSources(
    'app/src-tauri/src/commands/data/snapshot.rs',
    'app/src-tauri/src/commands/data/snapshot',
    'app/src-tauri/src/commands/sync/runtime/queue/seed.rs',
    'app/src-tauri/src/commands/sync/runtime/apply',
  );

  assert.doesNotMatch(
    source,
    /pub struct CurrentFocusRecord \{[\s\S]*pub task_ids: String,/,
    'current focus snapshots should store task_ids as arrays, not stringified JSON',
  );
  assert.doesNotMatch(
    source,
    /pub struct FocusScheduleRecord \{[\s\S]*pub blocks: String,/,
    'focus schedule snapshots should store blocks as arrays, not stringified JSON',
  );
  assert.doesNotMatch(
    source,
    /serde_json::to_string\(&task_ids\)|serde_json::from_str\(&plan\.task_ids\)|serde_json::to_string\(&blocks\)|serde_json::from_str\(&schedule\.blocks\)/,
    'snapshot import/export should not stringify or parse canonical task_ids/blocks arrays',
  );
  assert.doesNotMatch(
    source,
    /serde_json::Value::String\(s\)\s*=>\s*\{\s*serde_json::from_str\(s\)/s,
    'focus schedule sync apply should not preserve stringified blocks compatibility parsing',
  );
});

test('active contracts no longer preserve removed aliases or deprecated guide topics', () => {
  const source = readRustSources(
    'mcp-server/src/contract/workflow.rs',
    'mcp-server/src/system/guidance_support/mod.rs',
    'mcp-server/src/system/guidance_support/guide_render.rs',
    'mcp-server/src/system/guidance_support/guide_state.rs',
    'mcp-server/src/query/router.rs',
    'app/src/components/ai-memory/AIMemoryView.tsx',
  );

  assert.doesNotMatch(
    source,
    /FeatureIdea|feature_idea/,
    'feedback contracts should not keep the removed feature_idea alias',
  );
  assert.doesNotMatch(
    source,
    /DailyPlanning|daily_planning/,
    'guide contracts should not keep the deprecated daily_planning topic name',
  );
  assert.doesNotMatch(
    source,
    /project_summaries/,
    'AI memory view should not keep the removed project_summaries runtime alias',
  );
});

test('runtime DB locator no longer adopts Windows legacy DB paths', () => {
  const resolverSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-runtime/src/db_locator/resolve.rs'),
    'utf8',
  );
  const windowsSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-runtime/src/db_locator/platform_windows.rs'),
    'utf8',
  );
  const typesSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-runtime/src/db_locator/types.rs'),
    'utf8',
  );
  const moduleSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-runtime/src/db_locator/mod.rs'),
    'utf8',
  );

  for (const [label, source] of [
    ['runtime DB resolver', resolverSource],
    ['Windows platform helpers', windowsSource],
    ['DB locator result types', typesSource],
    ['DB locator module root', moduleSource],
  ]) {
    assert.doesNotMatch(
      source,
      /windows_legacy_candidates|WindowsLegacyPath|windows_legacy_path/,
      `${label} should not retain Windows legacy DB adoption plumbing`,
    );
  }
  assert.doesNotMatch(
    resolverSource,
    /Windows legacy DB locations|legacy location|legacy path|legacy-path/i,
    'resolver precedence and comments should not document removed Windows legacy adoption',
  );
});

test('compatibility re-export facades and key-alias shadows stay cleaned up', () => {
  const removedFrontendAliases = [
    'app/src/components/task-detail/TaskMetadataEditor.tsx',
    'app/src/components/task-detail/TaskNotesEditor.tsx',
  ];
  for (const relativePath of removedFrontendAliases) {
    assert.equal(
      fs.existsSync(path.join(repoRoot, relativePath)),
      false,
      `${relativePath} should not remain as a re-export-only compatibility alias`,
    );
  }

  const dayContextSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/dayContext.ts'), 'utf8');
  const frontendSource = readTypeScriptSources('app/src');
  const preferenceSource = readRustSources(
    'app/src/lib/query/usePreference.ts',
    'app/src/lib/notifications/preferences.ts',
    'app/src/components/calendar/calendarViewUtils.ts',
    'app/src/components/settings/settingsUtils.ts',
  );
  const queryKeyFactory = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/query/queryKeyFactory.ts'),
    'utf8',
  );
  const queryInvalidationHelpers = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/query/invalidation/helpers.ts'),
    'utf8',
  );
  const uiState = fs.readFileSync(path.join(repoRoot, 'app/src/lib/storage/uiState.ts'), 'utf8');
  const uiStateRuntimeTest = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/runtime/ui_state.test.ts'),
    'utf8',
  );
  const undoTokenStore = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/undoTokenStore.ts'),
    'utf8',
  );
  const undoTokenStoreRuntimeTest = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/runtime/undo-token-store.test.ts'),
    'utf8',
  );
  const storeLib = fs.readFileSync(path.join(repoRoot, 'lorvex-store/src/lib.rs'), 'utf8');
  const storeImport = fs.readFileSync(path.join(repoRoot, 'lorvex-store/src/import/mod.rs'), 'utf8');
  const syncTombstone = fs.readFileSync(path.join(repoRoot, 'lorvex-sync/src/tombstone/mod.rs'), 'utf8');

  assert.doesNotMatch(
    dayContextSource,
    /export \{[\s\S]*(addYmdDays|getNextMondayYmd|getNextWeekendYmd|isoFromDatetimeLocalInTimezone|ymdFromDateParts)[\s\S]*\};/,
    'dayContext.ts should not re-export pure dayContextMath helpers',
  );
  assert.doesNotMatch(
    frontendSource,
    /import \{[^}]*\b(addYmdDays|getNextMondayYmd|getNextWeekendYmd|isoFromDatetimeLocalInTimezone|ymdFromDateParts)\b[^}]*\} from ['"][^'"]*dayContext['"]/,
    'frontend code should import pure day-context helpers from dayContextMath directly',
  );

  assert.doesNotMatch(
    preferenceSource,
    /export \{[^}]*parse(?:Preference)?(?:Bool|Boolean|Json|String)[^}]*\}/,
    'preference parser helpers should not be re-exported through UI/runtime facade modules',
  );
  assert.doesNotMatch(
    preferenceSource,
    /export \{ timeToMinutes \}/,
    'notification preferences should import time utilities directly instead of re-exporting them',
  );

  assert.match(queryKeyFactory, /import type \{ DeviceStateKey \} from '\.\.\/preferences\/keys';/);
  assert.match(queryKeyFactory, /deviceState: \(key: DeviceStateKey\)/);
  assert.match(queryInvalidationHelpers, /import type \{ DeviceStateKey \} from '\.\.\/\.\.\/preferences\/keys';/);
  assert.match(queryInvalidationHelpers, /key: DeviceStateKey,/);

  assert.doesNotMatch(
    uiState,
    /export \{ createBrowserUIStateStorageHost \}/,
    'uiState.ts should not re-export browser storage hosts solely for tests',
  );
  assert.match(
    uiStateRuntimeTest,
    /from '\.\.\/\.\.\/\.\.\/app\/src\/lib\/storage\/uiState\.runtime';/,
    'ui_state runtime tests should import browser storage hosts from the runtime module directly',
  );
  assert.doesNotMatch(
    undoTokenStore,
    /export \{ createBrowserUndoTokenStorageHost \}/,
    'undoTokenStore.ts should not re-export browser storage hosts solely for tests',
  );
  assert.match(
    undoTokenStoreRuntimeTest,
    /from '\.\.\/\.\.\/\.\.\/app\/src\/lib\/undoTokenStore\.runtime';/,
    'undo-token runtime tests should import browser storage hosts from the runtime module directly',
  );

  for (const [label, source] of [
    ['lorvex-store lib root', storeLib],
    ['lorvex-store import module', storeImport],
    ['lorvex-sync tombstone module', syncTombstone],
  ]) {
    assert.doesNotMatch(
      source,
      /pre-#3372|old flat `[^`]+`|keep working without touching their `use` paths|consumers are not migrated/i,
      `${label} should not document compatibility-shim re-export intent`,
    );
    assert.match(
      source,
      /Intentional public API (?:hub|surface)/i,
      `${label} should document why its remaining re-export surface is still public`,
    );
  }
});
