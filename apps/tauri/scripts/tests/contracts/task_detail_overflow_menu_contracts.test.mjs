import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('task detail overflow menu delegates portal dismissal and positioning to shared anchored popup runtime', () => {
  const runtimePath = path.join(repoRoot, 'app/src/components/task-detail/content/TaskDetailContent.runtime.ts');
  const contentSource = readTypeScriptSources(
    'app/src/components/task-detail/content/TaskDetailContent.tsx',
    'app/src/components/task-detail/content/detail-content',
  );
  const runtimeSource = fs.readFileSync(runtimePath, 'utf8');

  assert.match(
    contentSource,
    /createBrowserAnchoredPopupDismissRuntimeDeps/,
    'TaskDetailContent should use the shared browser anchored popup ownership helper',
  );
  assert.match(
    contentSource,
    /installAnchoredPopupDismissRuntime/,
    'TaskDetailContent should install the shared anchored popup dismiss runtime',
  );
  assert.match(
    contentSource,
    /resolveAnchoredPopupPosition/,
    'TaskDetailContent should use shared anchored popup positioning',
  );
  assert.match(
    contentSource,
    /horizontalAlign:\s*'end'/,
    'TaskDetailContent should preserve its trailing-edge overflow-menu anchor',
  );
  assert.match(
    contentSource,
    /getPanel:\s*\(\)\s*=>\s*overflowPanelRef\.current/,
    'TaskDetailContent should include the portaled panel in inside-click detection',
  );
  assert.match(contentSource, /listenForScroll:\s*true/);
  assert.match(contentSource, /listenForResize:\s*true/);
  assert.doesNotMatch(
    runtimeSource,
    /installTaskDetailOverflowDismissRuntime|resolveTaskDetailOverflowPosition|shouldDismissTaskDetailOverflowFromTarget/,
    'TaskDetailContent.runtime should not carry a second task-detail-specific portal dismiss implementation',
  );
});

test('task detail overflow menu exposes ARIA menu semantics and keyboard navigation', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/detail-content/TaskDetailOverflowMenu.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/detail-content/TaskDetailOverflowMenu.runtime.ts'),
    'utf8',
  );

  assert.match(source, /aria-haspopup="menu"/);
  assert.match(source, /aria-expanded=\{overflowOpen\}/);
  assert.match(source, /aria-controls=\{overflowOpen \? overflowMenuId : undefined\}/);
  assert.match(source, /role="menu"/);
  assert.match(source, /role="menuitem"/);
  assert.match(source, /onKeyDown=\{handleOverflowPanelKeyDown\}/);
  assert.match(source, /focusFirstOverflowMenuItem/);
  assert.match(source, /resolveTaskDetailOverflowKeyAction/);
  assert.match(source, /focusTaskDetailOverflowMenuItem/);
  assert.match(runtimeSource, /ArrowDown/);
  assert.match(runtimeSource, /ArrowUp/);
  assert.match(runtimeSource, /Home/);
  assert.match(runtimeSource, /End/);
});
