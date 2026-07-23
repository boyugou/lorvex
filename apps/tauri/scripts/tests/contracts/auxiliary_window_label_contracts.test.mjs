import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

function readConfigWindowLabels(relativePath) {
  const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
  const config = JSON.parse(source);
  return (config.app?.windows ?? []).map((window) => window.label);
}

test('auxiliary window labels stay aligned between desktop Tauri configs and Rust accessors', () => {
  const configFiles = [
    'app/src-tauri/tauri.conf.json',
  ];
  const rustFiles = [
    'app/src-tauri/src/window_restore.rs',
    // Post-#3303 split: window_commands.rs is now a folder.
    'app/src-tauri/src/commands/ui/window_commands',
  ];

  const expectedLabels = ['popover'];

  for (const configFile of configFiles) {
    const labels = readConfigWindowLabels(configFile);
    for (const label of expectedLabels) {
      assert.ok(
        labels.includes(label),
        `${configFile} should define the ${label} auxiliary window label`,
      );
    }
  }

  for (const rustFile of rustFiles) {
    const absolutePath = path.join(repoRoot, rustFile);
    const source = fs.statSync(absolutePath).isDirectory() || rustFile === 'app/src-tauri/src/window_restore.rs'
      ? rustFile === 'app/src-tauri/src/window_restore.rs'
        ? readRustSources(rustFile, 'app/src-tauri/src/window_restore')
        : readRustSources(rustFile)
      : fs.readFileSync(absolutePath, 'utf8');
    const labels = Array.from(
      source.matchAll(/get_webview_window\("([^"]+)"\)/g),
      (item) => item[1],
    );
    const auxiliaryLabels = labels.filter((label) => expectedLabels.includes(label));

    assert.ok(
      auxiliaryLabels.length > 0,
      `${rustFile} should reference at least one auxiliary window label`,
    );

    for (const label of auxiliaryLabels) {
      assert.ok(
        expectedLabels.includes(label),
        `${rustFile} should only reference configured auxiliary window labels`,
      );
    }
  }
});

test('settings stays a main-window route instead of a dedicated desktop webview', () => {
  const tauriConfig = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/tauri.conf.json'), 'utf8');
  const appSource = fs.readFileSync(path.join(repoRoot, 'app/src/App.tsx'), 'utf8');
  const desktopShellSource = readRustSources('app/src-tauri/src/desktop_shell');
  const setupSource = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/setup_hook.rs'), 'utf8');
  const defaultCapability = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/capabilities/default.json'), 'utf8');
  const generatedCapabilityManifest = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/gen/schemas/capabilities.json'),
    'utf8',
  );
  const pluginSource = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/plugins.rs'), 'utf8');

  assert.doesNotMatch(
    tauriConfig,
    /"label"\s*:\s*"settings"|"url"\s*:\s*"index\.html#settings"/,
    'desktop config must not declare a hidden settings webview',
  );
  assert.doesNotMatch(
    appSource,
    /#settings|SettingsWindowApp|kind:\s*'settings'/,
    'React app shell must not retain a dedicated settings-window route',
  );
  assert.doesNotMatch(
    `${desktopShellSource}\n${setupSource}`,
    /settings_window|install_settings_close_to_hide|get_webview_window\("settings"\)/,
    'desktop shell must not retain close/hide plumbing for a removed settings webview',
  );
  assert.doesNotMatch(
    defaultCapability,
    /"settings"/,
    'default capability must not grant permissions to a removed settings window label',
  );
  assert.doesNotMatch(
    generatedCapabilityManifest,
    /"settings"/,
    'generated capability manifest must not retain a removed settings window label',
  );
  assert.doesNotMatch(
    pluginSource,
    /"settings"/,
    'window-state plugin denylist must not mention a removed settings window label',
  );
});
