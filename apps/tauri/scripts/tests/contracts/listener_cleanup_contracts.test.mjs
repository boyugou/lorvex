import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('late-resolving Tauri listeners clean themselves up after component disposal', () => {
  const memorySource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ai-memory/useAIMemoryViewController.ts'),
    'utf8',
  );
  const mainWindowSubscriptionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/runtime/useMainWindowSubscriptions.ts'),
    'utf8',
  );
  const mainWindowDeepLinkRuntimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/runtime/useMainWindowDeepLinkSubscription.runtime.ts'),
    'utf8',
  );
  const desktopMainWindowSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/DesktopMainWindow.tsx'),
    'utf8',
  );
  const menuEventsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/runtime/useMenuEvents.ts'),
    'utf8',
  );
  const popoverLifecycleSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/popover-window/controller/lifecycle.ts'),
    'utf8',
  );
  const shellEventToastsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/sync/useShellEventToasts.ts'),
    'utf8',
  );
  const externalMutationRuntimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/useExternalMutationSubscription.runtime.ts'),
    'utf8',
  );
  const listenerLifecycleSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/tauriListenerLifecycle.ts'),
    'utf8',
  );

  assert.match(
    mainWindowSubscriptionsSource,
    /import \{\s*startExternalMutationSubscriptionRuntime\s*\} from ['"](?:@\/lib|\.\.\/\.\.\/\.\.\/lib)\/useExternalMutationSubscription\.runtime['"];/,
    'main-window subscriptions should reuse the shared external-mutation runtime instead of reimplementing it locally',
  );

  assert.match(
    mainWindowSubscriptionsSource,
    /return startExternalMutationSubscriptionRuntime\(\{[\s\S]*ownWindowLabel: ownLabel,[\s\S]*listenMutationBroadcast:[\s\S]*listenDataChanged:/s,
    'main-window subscriptions should delegate mutation/data-changed listener lifecycle to the shared runtime',
  );

  assert.match(
    externalMutationRuntimeSource,
    /createAsyncTauriListenerScope\(\)[\s\S]*listeners\.add\(mutationListener,[\s\S]*listeners\.add\(dataChangedListener,[\s\S]*listeners\.dispose\(\)/s,
    'external mutation runtime should route late listener cleanup through the shared Tauri listener lifecycle helper',
  );

  assert.match(
    mainWindowSubscriptionsSource,
    /return startMainWindowDeepLinkSubscriptionRuntime\(\{[\s\S]*listenDeepLinkOpen:[\s\S]*listen<DeepLinkTarget>\('deep-link:\/\/open'/s,
    'main-window subscriptions should delegate deep-link listener lifecycle to the shared runtime seam',
  );

  assert.match(
    mainWindowDeepLinkRuntimeSource,
    /const listeners = createAsyncTauriListenerScope\(\);[\s\S]*const listenerPromise = listenDeepLinkOpen\(applyOpenPayload\);[\s\S]*listeners\.add\(listenerPromise,[\s\S]*listeners\.dispose\(\)/s,
    'main-window deep-link runtime should dispose late listeners through the shared lifecycle helper',
  );

  assert.match(
    memorySource,
    /const listeners = createAsyncTauriListenerScope\(\);[\s\S]*listeners\.add\([\s\S]*listen\('tauri:\/\/blur'[\s\S]*setMemoryLockState\(current => \(current\.lockEnabled \? \{ \.\.\.current, isLocked: true } : current\)\);[\s\S]*listeners\.dispose\(\)/s,
    'AI memory blur listener should dispose late listeners through the shared lifecycle helper',
  );

  assert.match(
    desktopMainWindowSource,
    /const listeners = createAsyncTauriListenerScope\(\);[\s\S]*listeners\.add\([\s\S]*listen\('menu:\/\/open-shortcuts'[\s\S]*setShowShortcuts\(true\);[\s\S]*listeners\.dispose\(\)/s,
    'DesktopMainWindow shortcut menu listener should dispose late listeners through the shared lifecycle helper',
  );

  assert.match(
    menuEventsSource,
    /const listeners = createAsyncTauriListenerScope\(\);[\s\S]*const addListener = <T = unknown>[\s\S]*listeners\.add\([\s\S]*listen<T>\(event,[\s\S]*listeners\.dispose\(\)/s,
    'main-window menu event bundle should centralize listener cleanup through the shared lifecycle helper',
  );

  assert.match(
    popoverLifecycleSource,
    /const listeners = createAsyncTauriListenerScope\(\);[\s\S]*listeners\.add\([\s\S]*listen\('tauri:\/\/blur'[\s\S]*listeners\.add\([\s\S]*listen\('tauri:\/\/focus'[\s\S]*listeners\.add\([\s\S]*listen\('tray:\/\/popover-opened'[\s\S]*listeners\.dispose\(\)/s,
    'popover lifecycle listeners should dispose through the shared lifecycle helper',
  );

  assert.equal(
    fs.existsSync(path.join(repoRoot, 'app/src/components/ui/ICloudReauthBanner.runtime.ts')),
    false,
    'retired iCloud reauth runtime should not be required for listener cleanup coverage',
  );

  assert.match(
    shellEventToastsSource,
    /const translateRef = useRef\(t\);[\s\S]*translateRef\.current = t;[\s\S]*const listeners = createAsyncTauriListenerScope\(\);[\s\S]*subscribe<SyncNoticePayload>[\s\S]*translateRef\.current\(key as TranslationKey\)[\s\S]*subscribe<DataResetFailedPayload>[\s\S]*translateRef\.current\('shellEvents\.dataResetFailed'\)[\s\S]*subscribe<NotificationActionErrorPayload>[\s\S]*translateRef\.current\('shellEvents\.notificationActionFailed'\)[\s\S]*listeners\.dispose\(\);[\s\S]*}, \[\]\);/s,
    'shell event toast listeners should stay mounted across locale/callback changes while reading latest translations through refs',
  );

  assert.match(
    listenerLifecycleSource,
    /if \(disposed\) \{[\s\S]*safelyUnlisten\(unlisten\);[\s\S]*return;[\s\S]*}\s*unlisteners\.add\(unlisten\);/s,
    'shared lifecycle helper should immediately unlisten registrations that resolve after disposal',
  );
});
