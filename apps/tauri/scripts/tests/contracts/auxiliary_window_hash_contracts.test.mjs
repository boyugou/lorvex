import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readAppSources, readRustSources, repoRoot } from './shared.mjs';

function readConfigWindowUrls(relativePath) {
  const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
  const config = JSON.parse(source);
  const windows = config.app?.windows ?? [];
  return new Map(windows.map((window) => [window.label, window.url]));
}

function readConfigWindow(relativePath, label) {
  const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
  const config = JSON.parse(source);
  return (config.app?.windows ?? []).find((window) => window.label === label) ?? null;
}

function readStringConstant(source, pattern, description, groupIndex = 1) {
  const match = source.match(pattern);
  assert.ok(match, `Expected ${description}`);
  return match[groupIndex];
}

test('desktop Tauri config variants keep the popover hash route aligned with App.tsx routing', () => {
  const appSource = readAppSources();
  const configFiles = [
    'app/src-tauri/tauri.conf.json',
  ];

  // App.tsx centralizes window-hash routing through a typed
  // `WINDOW_HASH` constant + `resolveWindowKind` dispatcher.
  const popoverHash = readStringConstant(
    appSource,
    /WINDOW_HASH = \{[\s\S]*?popover: '([^']+)',/,
    'popover hash route in App.tsx WINDOW_HASH constant',
  );

  for (const configFile of configFiles) {
    const windowUrls = readConfigWindowUrls(configFile);
    assert.equal(
      windowUrls.get('popover'),
      `index.html${popoverHash}`,
      `${configFile} should keep the popover window URL aligned with App.tsx hash routing`,
    );
  }
});

test('popover rebuild helper stays aligned with desktop Tauri popover window config', () => {
  const desktopShellSource = readRustSources('app/src-tauri/src/desktop_shell');
  const configFiles = [
    'app/src-tauri/tauri.conf.json',
  ];

  const popoverTitle = readStringConstant(
    desktopShellSource,
    /const POPOVER_WINDOW_TITLE: &str = "([^"]+)";/,
    'POPOVER_WINDOW_TITLE in the desktop_shell module tree',
  );
  const popoverHashRoute = readStringConstant(
    desktopShellSource,
    /const POPOVER_WINDOW_HASH_ROUTE: &str = "([^"]+)";/,
    'POPOVER_WINDOW_HASH_ROUTE in the desktop_shell module tree',
  );
  const popoverWidth = Number(readStringConstant(
    desktopShellSource,
    /const POPOVER_WINDOW_WIDTH: f64 = ([\d.]+);/,
    'POPOVER_WINDOW_WIDTH in the desktop_shell module tree',
  ));
  const popoverHeight = Number(readStringConstant(
    desktopShellSource,
    /const POPOVER_WINDOW_HEIGHT: f64 = ([\d.]+);/,
    'POPOVER_WINDOW_HEIGHT in the desktop_shell module tree',
  ));

  assert.match(desktopShellSource, /\.resizable\(false\)/, 'Rebuilt popovers should remain non-resizable');
  assert.match(desktopShellSource, /\.decorations\(false\)/, 'Rebuilt popovers should remain undecorated');
  assert.match(desktopShellSource, /\.shadow\(false\)/, 'Rebuilt popovers should keep shadow disabled');
  assert.match(desktopShellSource, /\.always_on_top\(true\)/, 'Rebuilt popovers should remain always-on-top');
  assert.match(desktopShellSource, /\.visible\(false\)/, 'Rebuilt popovers should stay hidden until explicitly presented');

  for (const configFile of configFiles) {
    const popoverWindow = readConfigWindow(configFile, 'popover');
    assert.ok(popoverWindow, `${configFile} should define a popover window`);
    assert.equal(popoverWindow.title, popoverTitle, `${configFile} popover title should match desktop_shell rebuild constants`);
    assert.equal(Number(popoverWindow.width), popoverWidth, `${configFile} popover width should match desktop_shell rebuild constants`);
    assert.equal(Number(popoverWindow.height), popoverHeight, `${configFile} popover height should match desktop_shell rebuild constants`);
    assert.equal(popoverWindow.url, popoverHashRoute, `${configFile} popover URL should match desktop_shell rebuild constants`);
    assert.equal(popoverWindow.resizable, false, `${configFile} popover should stay non-resizable`);
    assert.equal(popoverWindow.decorations, false, `${configFile} popover should stay undecorated`);
    assert.equal(popoverWindow.shadow, false, `${configFile} popover should keep shadow disabled`);
    assert.equal(popoverWindow.alwaysOnTop, true, `${configFile} popover should stay always-on-top`);
    assert.equal(popoverWindow.visible, false, `${configFile} popover should stay hidden until presented`);
  }
});
