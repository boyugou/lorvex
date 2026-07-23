import assert from 'node:assert/strict';
import test from 'node:test';

import {
  installMainDocumentRuntime,
  isTransparentOverlayWindow,
  resolveCurrentWindowLabel,
  resolveWindowKind,
  syncDocumentVisibilityAttr,
} from '../../../app/src/main.runtime';

function createDocumentHarness(initialVisibility = 'visible') {
  const attrs = new Map<string, string>();
  const listeners = new Map<string, () => void>();
  return {
    attrs,
    listeners,
    documentTarget: {
      addEventListener: (type: 'visibilitychange', listener: () => void) => {
        listeners.set(type, listener);
      },
      documentElement: {
        removeAttribute: (name: string) => {
          attrs.delete(name);
        },
        setAttribute: (name: string, value: string) => {
          attrs.set(name, value);
        },
      },
      visibilityState: initialVisibility,
    },
  };
}

test('main runtime resolves Tauri window labels and falls back to main', () => {
  assert.equal(resolveCurrentWindowLabel({}), 'main');
  assert.equal(resolveCurrentWindowLabel({ __TAURI_INTERNALS__: { metadata: { currentWindow: { label: '' } } } }), 'main');
  assert.equal(
    resolveCurrentWindowLabel({ __TAURI_INTERNALS__: { metadata: { currentWindow: { label: 'focus' } } } }),
    'focus',
  );
});

test('main runtime classifies main versus overlay windows and transparent overlays', () => {
  assert.equal(resolveWindowKind('main'), 'main');
  assert.equal(resolveWindowKind('settings'), 'overlay');
  assert.equal(isTransparentOverlayWindow('focus'), true);
  assert.equal(isTransparentOverlayWindow('popover'), true);
  assert.equal(isTransparentOverlayWindow('settings'), false);
});

test('main runtime applies document platform/window attributes and installs visibility sync once', () => {
  const harness = createDocumentHarness('hidden');
  const windowTarget = {
    __TAURI_INTERNALS__: { metadata: { currentWindow: { label: 'focus' } } },
    __lorvexVisibilityAttrInstalled: false,
  };

  const result = installMainDocumentRuntime({
    desktopPlatform: 'macos',
    documentTarget: harness.documentTarget,
    mobilePlatform: 'android',
    windowTarget,
  });

  assert.deepEqual(result, {
    installedVisibilityListener: true,
    windowKind: 'overlay',
    windowLabel: 'focus',
  });
  assert.equal(harness.attrs.get('data-window-kind'), 'overlay');
  assert.equal(harness.attrs.get('data-window-transparent'), '');
  assert.equal(harness.attrs.get('data-desktop-os'), 'macos');
  assert.equal(harness.attrs.get('data-mobile-os'), 'android');
  assert.equal(harness.attrs.get('data-visibility'), 'hidden');
  assert.equal(windowTarget.__lorvexVisibilityAttrInstalled, true);

  harness.documentTarget.visibilityState = 'visible';
  harness.listeners.get('visibilitychange')?.();
  assert.equal(harness.attrs.get('data-visibility'), 'visible');
});

test('main runtime refreshes visibility attr but skips duplicate listener installation', () => {
  const harness = createDocumentHarness('hidden');
  harness.attrs.set('data-window-transparent', '');
  const windowTarget = { __lorvexVisibilityAttrInstalled: true };

  const result = installMainDocumentRuntime({
    desktopPlatform: 'windows',
    documentTarget: harness.documentTarget,
    mobilePlatform: 'unknown',
    windowTarget,
  });

  assert.deepEqual(result, {
    installedVisibilityListener: false,
    windowKind: 'main',
    windowLabel: 'main',
  });
  assert.equal(harness.attrs.get('data-window-kind'), 'main');
  assert.equal(harness.attrs.has('data-window-transparent'), false);
  assert.equal(harness.attrs.get('data-visibility'), 'hidden');
  assert.deepEqual([...harness.listeners.keys()], []);
});

test('main runtime exposes direct visibility attr sync for listener callbacks', () => {
  const harness = createDocumentHarness('prerender');
  syncDocumentVisibilityAttr(harness.documentTarget);
  assert.equal(harness.attrs.get('data-visibility'), 'prerender');
});
