import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readAppSources, readTypeScriptSources, repoRoot } from './shared.mjs';

test('App root delegates main-window runtime to a dedicated app-shell subsystem', () => {
  const appRootSource = fs.readFileSync(path.join(repoRoot, 'app/src/App.tsx'), 'utf8');
  const appShellSource = readTypeScriptSources('app/src/app-shell');
  const mainWindowSource = readTypeScriptSources('app/src/app-shell/main-window');
  const mainWindowDir = path.join(repoRoot, 'app/src/app-shell/main-window');

  assert.match(
    appRootSource,
    /const MainWindowApp = lazy\(\(\) =>[\s\S]{0,120}import\('\.\/app-shell\/MainWindowApp'\)/,
    'App.tsx should lazy-load the main-window runtime from the dedicated app-shell subsystem',
  );
  assert.match(
    appRootSource,
    /<MainWindowApp runtimeProfile=\{runtimeProfile} \/>/,
    'App.tsx should route the main window through the dedicated app-shell composition root',
  );
  assert.doesNotMatch(
    appRootSource,
    /function MainWindowApp\(/,
    'App.tsx should not keep the main-window runtime inline after extraction',
  );

  assert.match(
    appShellSource,
    /export function MainWindowApp\(\{ runtimeProfile }/,
    'app-shell should expose a dedicated MainWindowApp composition root',
  );
  assert.equal(
    fs.existsSync(path.join(mainWindowDir, 'useMainWindowController.ts')),
    true,
    'app-shell should keep main-window runtime state in a dedicated controller module',
  );
  assert.equal(
    fs.existsSync(path.join(mainWindowDir, 'DesktopMainWindow.tsx')),
    true,
    'app-shell should keep desktop main-window layout in a dedicated desktop shell module',
  );
  assert.equal(
    fs.existsSync(path.join(mainWindowDir, 'MobileMainWindow.tsx')),
    true,
    'app-shell should keep mobile main-window layout in a dedicated mobile shell module',
  );
  assert.equal(
    fs.existsSync(path.join(mainWindowDir, 'types.ts')),
    true,
    'app-shell should keep main-window controller types in a dedicated shared types module',
  );
  assert.equal(
    fs.existsSync(path.join(mainWindowDir, 'useMainWindowActions.ts')),
    true,
    'app-shell should keep window chrome and focus actions in a dedicated main-window actions module',
  );
  assert.equal(
    fs.existsSync(path.join(mainWindowDir, 'useMainWindowNavigation.ts')),
    true,
    'app-shell should keep main-window navigation state in a dedicated navigation module',
  );
  assert.match(
    appShellSource,
    /import \{ DesktopMainWindow } from '\.\/main-window\/DesktopMainWindow';/,
    'MainWindowApp should delegate desktop rendering to the main-window desktop shell',
  );
  assert.match(
    appShellSource,
    /import \{ MobileMainWindow } from '\.\/main-window\/MobileMainWindow';/,
    'MainWindowApp should delegate mobile rendering to the main-window mobile shell',
  );
  assert.match(
    appShellSource,
    /import \{ useMainWindowController } from '\.\/main-window\/useMainWindowController';/,
    'MainWindowApp should delegate runtime orchestration to the main-window controller module',
  );
  assert.match(
    mainWindowSource,
    /import type \{ MainWindowController } from '\.\/types';/,
    'main-window desktop and mobile shells should consume shared controller types from a dedicated types module',
  );
  assert.match(
    mainWindowSource,
    /import \{ useMainWindowActions } from '\.\/useMainWindowActions';/,
    'main-window controller should delegate window chrome and focus actions to the dedicated actions module',
  );
  assert.match(
    mainWindowSource,
    /import \{ useMainWindowNavigation } from '\.\/useMainWindowNavigation';/,
    'main-window controller should delegate navigation and list selection state to the dedicated navigation module',
  );
  assert.match(
    mainWindowSource,
    /export interface MainWindowController \{/,
    'main-window should expose a shared controller contract for desktop and mobile shells',
  );
  assert.match(
    appShellSource,
    /export function mapViewToSidebarModule\(view: View\): SidebarModule \| null \{/,
    'app-shell support should own the main-window sidebar-module mapping helper',
  );
  const aggregatedAppSource = readAppSources();
  assert.match(
    aggregatedAppSource,
    /const executeAssistantUiCommand = useCallback\(async \(command: AssistantUiCommand\) => \{/,
    'the canonical App source tree should still expose the assistant UI command runtime after extraction',
  );
});

test('mobile task detail modal lets ModalShell move focus into the fullscreen dialog', () => {
  const mobileSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/MobileMainWindow.tsx'),
    'utf8',
  );
  const selectedTaskModal = mobileSource.match(
    /\{selectedTaskId !== null && \([\s\S]*?<ModalShell(?<props>[\s\S]*?)>\s*<ErrorBoundary/,
  );

  assert.ok(selectedTaskModal?.groups?.props, 'MobileMainWindow should render selected tasks through ModalShell');
  assert.match(
    selectedTaskModal.groups.props,
    /ariaLabel=\{t\('task\.title'\)\}/,
    'the fullscreen task detail dialog should remain labelled',
  );
  assert.doesNotMatch(
    selectedTaskModal.groups.props,
    /autoFocus=\{false\}/,
    'the fullscreen task detail dialog must not leave focus outside the inert app background',
  );
});
