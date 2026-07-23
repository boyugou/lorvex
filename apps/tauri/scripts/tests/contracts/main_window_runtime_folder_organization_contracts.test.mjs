import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('main-window controller delegates runtime effects to a coherent runtime subtree', () => {
  const mainWindowDir = path.join(repoRoot, 'app/src/app-shell/main-window');
  const runtimeDir = path.join(mainWindowDir, 'runtime');
  const controllerSource = fs.readFileSync(path.join(mainWindowDir, 'useMainWindowController.ts'), 'utf8');
  const runtimeSource = readTypeScriptSources('app/src/app-shell/main-window/runtime');

  assert.equal(
    fs.existsSync(runtimeDir),
    true,
    'main-window should keep effect-heavy controller concerns in a dedicated runtime subtree',
  );
  assert.equal(
    fs.existsSync(path.join(runtimeDir, 'useAssistantUiRuntime.ts')),
    true,
    'main-window runtime should isolate assistant UI command polling in a dedicated runtime module',
  );
  assert.equal(
    fs.existsSync(path.join(runtimeDir, 'useBackgroundMaintenance.ts')),
    true,
    'main-window runtime should isolate startup maintenance in a dedicated runtime module',
  );
  assert.equal(
    fs.existsSync(path.join(runtimeDir, 'useMainWindowShortcuts.ts')),
    true,
    'main-window runtime should isolate keyboard shortcut orchestration in a dedicated runtime module',
  );
  assert.equal(
    fs.existsSync(path.join(runtimeDir, 'useMainWindowSubscriptions.ts')),
    true,
    'main-window runtime should isolate mutation and deep-link subscriptions in a dedicated runtime module',
  );

  assert.match(
    controllerSource,
    /import \{ useAssistantUiRuntime } from '\.\/runtime\/useAssistantUiRuntime';/,
    'main-window controller should delegate assistant UI polling to the runtime subtree',
  );
  assert.match(
    controllerSource,
    /import \{ useBackgroundMaintenance } from '\.\/runtime\/useBackgroundMaintenance';/,
    'main-window controller should delegate background maintenance to the runtime subtree',
  );
  assert.match(
    controllerSource,
    /import \{ useMainWindowShortcuts } from '\.\/runtime\/useMainWindowShortcuts';/,
    'main-window controller should delegate keyboard shortcuts to the runtime subtree',
  );
  assert.match(
    controllerSource,
    /import \{ useMainWindowSubscriptions } from '\.\/runtime\/useMainWindowSubscriptions';/,
    'main-window controller should delegate event subscriptions to the runtime subtree',
  );
  assert.doesNotMatch(
    controllerSource,
    /const executeAssistantUiCommand = useCallback\(|window\.addEventListener\('keydown'|consumePendingDeepLink\(/,
    'main-window controller should remain a composition root after runtime extraction',
  );

  assert.match(
    runtimeSource,
    /export function useAssistantUiRuntime\(/,
    'runtime subtree should expose a dedicated assistant UI runtime hook',
  );
  assert.match(
    runtimeSource,
    /export function useBackgroundMaintenance\(/,
    'runtime subtree should expose a dedicated background maintenance hook',
  );
  assert.match(
    runtimeSource,
    /export function useMainWindowShortcuts\(/,
    'runtime subtree should expose a dedicated keyboard shortcut hook',
  );
  assert.match(
    runtimeSource,
    /export function useMainWindowSubscriptions\(/,
    'runtime subtree should expose a dedicated event subscription hook',
  );
});
