import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

// Audit #2690: the first-paint path used to fire 15+ sequential
// `invoke()` calls before the main window could render. The fix is
// the `get_today_bootstrap` command + matching TS wrapper, seeded
// into the per-field query cache by `useMainWindowQueries`. Lock
// that wiring so an accidental revert or rename shows up as a test
// failure instead of a silent regression on first-paint latency.

test('bootstrap ipc wrapper owns get_today_bootstrap directly', () => {
  const bootstrapSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/ipc/bootstrap.ts'),
    'utf8',
  );
  assert.match(
    bootstrapSource,
    /export\s+interface\s+TodayBootstrap/,
    'bootstrap.ts must declare the TodayBootstrap payload type',
  );
  assert.match(
    bootstrapSource,
    /invoke\(['"]get_today_bootstrap['"]/,
    'bootstrap.ts must invoke the backend command exactly by name',
  );
});

test('useMainWindowQueries drives first paint off the bootstrap and seeds per-field queries', () => {
  const hookSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/useMainWindowQueries.ts'),
    'utf8',
  );
  const bootstrapCacheSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/query/bootstrapCache.ts'),
    'utf8',
  );
  const preferenceCacheSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/query/preferenceCache.ts'),
    'utf8',
  );
  const source = `${hookSource}\n${bootstrapCacheSource}\n${preferenceCacheSource}`;

  // The hook must key on the bootstrap queryKey head — not the
  // legacy per-field overview/lists heads — so descendants observing
  // those heads read from a seeded cache rather than firing IPC.
  assert.match(
    hookSource,
    /queryKey:\s*QUERY_KEYS\.todayBootstrap\(\)/,
    'useMainWindowQueries must key its primary query through QUERY_KEYS.todayBootstrap()',
  );
  assert.match(
    hookSource,
    /getTodayBootstrap\(signal\)/,
    'useMainWindowQueries must call getTodayBootstrap as its IPC entrypoint',
  );

  // Seeding the per-field cache is what lets the 15+ downstream
  // queries skip their own `invoke()` on mount. The reviewer
  // checklist calls out each key head we commit to seeding. The
  // hook may seed via `queryClient.setQueryData` directly or via a
  // local helper (e.g. `seedHead(QK.overview, …)`), so we just
  // require the head identifier appears paired with a query-cache
  // write path in the file.
  for (const head of [
    'QK.overview',
    'QK.lists',
    'QK.currentFocus',
    'QK.setupStatus',
    'QK.preference',
  ]) {
    assert.ok(
      source.includes(head),
      `useMainWindowQueries must reference ${head} when seeding the bootstrap payload`,
    );
  }
  assert.match(
    bootstrapCacheSource,
    /setQueryData/,
    'bootstrap cache seeding must write seed values via queryClient.setQueryData',
  );
  assert.match(
    bootstrapCacheSource,
    /setQueryDefaults/,
    'bootstrap cache seeding must bump staleTime for seeded heads so descendants do not re-fire IPC on mount',
  );

  // The legacy direct IPC entrypoints must NOT be called from the
  // first-paint hook — that would re-introduce the waterfall the
  // bootstrap was built to eliminate.
  assert.doesNotMatch(
    hookSource,
    /getOverview\(signal\)/,
    'first-paint hook must not re-introduce a direct getOverview call',
  );
  assert.doesNotMatch(
    hookSource,
    /getAllLists\(signal\)/,
    'first-paint hook must not re-introduce a direct getAllLists call',
  );
});

test('get_today_bootstrap is exposed to the generated rust handler list', () => {
  const libSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/lib.rs'),
    'utf8',
  );
  assert.match(libSource, /commands::apply_invoke_handlers\(builder\)/);

  const commandsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );
  assert.match(
    commandsSource,
    /^pub\(crate\) mod bootstrap;$/m,
    'commands.rs must register the bootstrap command module',
  );

  const bootstrapSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/bootstrap.rs'),
    'utf8',
  );
  assert.match(bootstrapSource, /#\[tauri::command\][\s\S]*?pub fn get_today_bootstrap\(\)/);

  const buildScriptSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/build.rs'),
    'utf8',
  );
  assert.match(buildScriptSource, /walk_rs\(&src\.join\("commands"\), &mut files\);/);
});
