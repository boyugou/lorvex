import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const SERVICES_DIR = path.join(repoRoot, 'app/src-tauri/src/commands/app_services');

function readAllSourcesUnder(dir) {
  let combined = '';
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const child = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      combined += readAllSourcesUnder(child);
    } else if (entry.isFile() && entry.name.endsWith('.rs')) {
      combined += `\n// ===== ${entry.name} =====\n`;
      combined += fs.readFileSync(child, 'utf8');
    }
  }
  return combined;
}

test('root app service commands live in a dedicated app_services module', () => {
  const commandsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );
  // Post-#4109, handler registration points at command leaf modules directly.
  // commands.rs owns only the module boundary plus non-IPC orchestration helpers.
  const servicesSource = readAllSourcesUnder(SERVICES_DIR);

  assert.match(
    commandsSource,
    /^pub\(crate\) mod app_services;$/m,
    'commands.rs should register the app_services command module for generated handlers',
  );
  assert.doesNotMatch(
    commandsSource,
    /\n#\[tauri::command\]\npub async fn check_for_update\(|\n#\[tauri::command\]\npub async fn authenticate_biometrics\(/,
    'commands.rs should not keep app service IPC inline after extraction',
  );
  for (const symbol of [
    /\n#\[tauri::command\]\npub async fn check_for_update\(/,
    /\n#\[tauri::command\]\npub async fn authenticate_biometrics\(/,
  ]) {
    assert.match(
      servicesSource,
      symbol,
      `expected app_services/ subtree to contain ${symbol}`,
    );
  }
});
