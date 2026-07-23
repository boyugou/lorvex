import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, readTypeScriptSources } from './shared.mjs';

function readStringConstant(source, pattern, description, groupIndex = 1) {
  const match = source.match(pattern);
  assert.ok(match, `Expected ${description}`);
  return match[groupIndex];
}

function readExportedStringConstant(source, name, description = name) {
  return readStringConstant(
    source,
    new RegExp(`export const ${name} = '([^']+)';`),
    description,
  );
}

function readCanonicalAlias(source, exportedName, description) {
  return readStringConstant(
    source,
    new RegExp(`export const ${exportedName} = (DEV_[A-Z0-9_]+);`),
    description,
  );
}

function readDomainStringConstant(source, name) {
  return readStringConstant(
    source,
    new RegExp(`pub const ${name}: &str = "([^"]+)";`),
    `${name} in lorvex-domain preference key registry`,
  );
}

function readRustAssistantUiPreferenceKey(source, domainSource, exportedName) {
  const literal = source.match(new RegExp(`${exportedName}: &str = "([^"]+)";`));
  if (literal) {
    return literal[1];
  }
  const alias = source.match(
    new RegExp(`${exportedName}: &str =\\s*lorvex_domain::preference_keys::([A-Z0-9_]+);`),
  );
  assert.ok(alias, `Expected ${exportedName} literal or domain registry alias in server_preferences_ui/mod.rs`);
  return readDomainStringConstant(domainSource, alias[1]);
}

function readAssistantUiPreferenceKeysFromRust(source, domainSource) {
  const match = source.match(
    /ASSISTANT_UI_COMMAND_KEY: &str = "([^"]+)";[\s\S]*ASSISTANT_UI_HANDLED_ID_KEY: &str = "([^"]+)";/,
  );
  if (match) {
    return {
      commandKey: match[1],
      handledKey: match[2],
    };
  }
  return {
    commandKey: readRustAssistantUiPreferenceKey(source, domainSource, 'ASSISTANT_UI_COMMAND_KEY'),
    handledKey: readRustAssistantUiPreferenceKey(source, domainSource, 'ASSISTANT_UI_HANDLED_ID_KEY'),
  };
}

test('assistant UI command preference keys stay aligned between Rust producer and app consumer', () => {
  const rustSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/preferences/ui/mod.rs'), 'utf8');
  const domainPreferenceKeysSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-domain/src/preference_keys/mod.rs'),
    'utf8',
  );
  const appSupportSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/support.tsx'),
    'utf8',
  );
  const preferenceKeysSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/preferences/keys.ts'),
    'utf8',
  );

  const { commandKey: rustCommandKey, handledKey: rustHandledKey } = readAssistantUiPreferenceKeysFromRust(
    rustSource,
    domainPreferenceKeysSource,
  );
  const appCommandAlias = readCanonicalAlias(
    appSupportSource,
    'ASSISTANT_UI_COMMAND_KEY',
    'ASSISTANT_UI_COMMAND_KEY in app-shell/support.tsx',
  );
  const appHandledAlias = readCanonicalAlias(
    appSupportSource,
    'ASSISTANT_UI_HANDLED_ID_KEY',
    'ASSISTANT_UI_HANDLED_ID_KEY in app-shell/support.tsx',
  );
  const appCommandKey = readExportedStringConstant(preferenceKeysSource, appCommandAlias);
  const appHandledKey = readExportedStringConstant(preferenceKeysSource, appHandledAlias);

  assert.equal(
    appCommandKey,
    rustCommandKey,
    'App.tsx should consume the same assistant_ui_command preference key that Rust writes',
  );
  assert.equal(
    appHandledKey,
    rustHandledKey,
    'App.tsx should consume the same assistant_ui_command_handled_id preference key that Rust writes',
  );
});

test('AI memory lock preference key stays aligned between the general settings controller and AIMemoryView', () => {
  const generalControllerSource = readTypeScriptSources(
    'app/src/components/settings/controller/useGeneralSettingsController.ts',
    'app/src/components/settings/controller/general',
  );
  const memorySource = fs.readFileSync(path.join(repoRoot, 'app/src/components/ai-memory/AIMemoryView.tsx'), 'utf8');
  const preferenceKeysSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/preferences/keys.ts'),
    'utf8',
  );

  assert.match(
    preferenceKeysSource,
    /export const PREF_MEMORY_LOCK_ENABLED = 'memory_lock_enabled';/,
    'preferenceKeys.ts should own the canonical memory lock preference key',
  );
  assert.match(
    generalControllerSource,
    /PREF_MEMORY_LOCK_ENABLED/,
    'general settings controller should consume PREF_MEMORY_LOCK_ENABLED instead of duplicating the key',
  );
  assert.match(
    memorySource,
    /PREF_MEMORY_LOCK_ENABLED/,
    'AIMemoryView should consume PREF_MEMORY_LOCK_ENABLED instead of duplicating the key',
  );
});
