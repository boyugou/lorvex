import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { getRuntimeId } from '../../../app/src/lib/platform/platform';
import {
  buildRuntimeProfile,
  detectDesktopPlatform,
  detectMobilePlatform,
  getClaudeCodeConfigPathHintForRuntime,
  getClaudeDesktopConfigPathHintForRuntime,
  getCodexConfigPathHintForRuntime,
  resolveRuntimeId,
  type RuntimeNavigatorSnapshot,
} from '../../../app/src/lib/platform/platform.logic';
import { readRuntimeNavigatorSnapshot } from '../../../app/src/lib/platform/platform.runtime';

function snapshot(userAgent: string, maxTouchPoints: number = 0): RuntimeNavigatorSnapshot {
  return { userAgent, maxTouchPoints };
}

test('platform detection: desktop runtimes resolve from canonical user agents', () => {
  assert.equal(
    detectDesktopPlatform(snapshot('Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0_0) AppleWebKit/605.1.15')),
    'macos',
  );
  assert.equal(
    detectDesktopPlatform(snapshot('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')),
    'windows',
  );
  assert.equal(
    detectDesktopPlatform(snapshot('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36')),
    'linux',
  );
});

test('platform detection: Android mobile runtimes outrank desktop detection while desktop-class mobile UA stays macOS', () => {
  const desktopClassMobileUa = snapshot(
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1',
    5,
  );
  assert.equal(detectMobilePlatform(desktopClassMobileUa), 'unknown');
  assert.equal(detectDesktopPlatform(desktopClassMobileUa), 'macos');
  assert.equal(resolveRuntimeId(desktopClassMobileUa), 'macos');

  const androidUa = snapshot('Mozilla/5.0 (Linux; Android 15; Pixel Tablet) AppleWebKit/537.36');
  assert.equal(detectMobilePlatform(androidUa), 'android');
  assert.equal(detectDesktopPlatform(androidUa), 'unknown');
  assert.equal(resolveRuntimeId(androidUa), 'android');
});

test('platform detection: null snapshot fails closed to unknown runtime', () => {
  assert.equal(detectMobilePlatform(null), 'unknown');
  assert.equal(detectDesktopPlatform(null), 'unknown');
  assert.equal(resolveRuntimeId(null), 'unknown');
});

test('platform runtime reads navigator snapshots through a guarded host seam', () => {
  const original = Object.getOwnPropertyDescriptor(globalThis, 'navigator');

  try {
    Object.defineProperty(globalThis, 'navigator', {
      configurable: true,
      value: {
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        maxTouchPoints: 0,
      },
    });
    assert.deepEqual(readRuntimeNavigatorSnapshot(), {
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      maxTouchPoints: 0,
    });
    assert.equal(getRuntimeId(), 'windows');

    Object.defineProperty(globalThis, 'navigator', {
      configurable: true,
      value: undefined,
    });
    assert.equal(readRuntimeNavigatorSnapshot(), null);
  } finally {
    if (original) {
      Object.defineProperty(globalThis, 'navigator', original);
    } else {
      Reflect.deleteProperty(globalThis, 'navigator');
    }
  }
});

test('platform facade delegates navigator access to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/platform/platform.ts'),
    'utf8',
  );

  assert.match(source, /import \{ readRuntimeNavigatorSnapshot \} from '\.\/platform\.runtime';/);
  assert.doesNotMatch(source, /\bnavigator\b/);
});

test('runtime profile: windows and macOS advertise the expected sync + native capability mix', () => {
  const windows = buildRuntimeProfile('windows');
  assert.equal(windows.runtimeClass, 'desktop');
  assert.equal(windows.supportsMcpHosting, true);
  assert.equal(windows.supportedSyncBackendKinds.includes('filesystem_bridge'), true);
  assert.equal(windows.supportedSyncBackendKinds.includes('remote_provider'), false);
  assert.equal(windows.nativeCalendarAdapterKind, 'windows_appointments');

  const macos = buildRuntimeProfile('macos');
  assert.equal(macos.supportedSyncBackendKinds.includes('remote_provider'), false);
  assert.equal(macos.supportedSyncBackendKinds.includes('filesystem_bridge'), true);
  assert.equal(macos.trayPresentationKind, 'menu_bar');
  assert.equal(macos.biometricAdapterKind, 'touch_id');
});

test('config path hints: runtime-specific helpers return windows vs unix layouts', () => {
  assert.equal(
    getClaudeDesktopConfigPathHintForRuntime('windows'),
    '%APPDATA%\\Claude\\claude_desktop_config.json',
  );
  assert.equal(
    getClaudeDesktopConfigPathHintForRuntime('linux'),
    '~/.config/Claude/claude_desktop_config.json',
  );
  assert.equal(
    getClaudeDesktopConfigPathHintForRuntime('macos'),
    '~/Library/Application Support/Claude/claude_desktop_config.json',
  );
  assert.equal(getClaudeCodeConfigPathHintForRuntime('windows'), '%USERPROFILE%\\.claude.json');
  assert.equal(getClaudeCodeConfigPathHintForRuntime('linux'), '~/.claude.json');
  assert.equal(getCodexConfigPathHintForRuntime('windows'), '%USERPROFILE%\\.codex\\config.toml');
  assert.equal(getCodexConfigPathHintForRuntime('android'), '~/.codex/config.toml');
});
