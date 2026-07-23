import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_preferences is organized as a folder-backed subsystem with storage, vocabulary, and tests modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/preferences/mod.rs'),
    'utf8',
  );
  const storageSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/preferences/storage.rs'),
    'utf8',
  );
  const vocabularySource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/preferences/vocabulary.rs'),
    'utf8',
  );
  const testsSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/preferences/tests.rs'),
    'utf8',
  );

  assert.match(rootSource, /^mod storage;$/m);
  assert.match(rootSource, /^mod vocabulary;$/m);
  assert.match(rootSource, /^#\[cfg\(test\)\]$/m);
  assert.match(rootSource, /^mod tests;$/m);
  assert.match(rootSource, /^pub\(crate\) use storage::/m);
  assert.match(rootSource, /^pub\(crate\) use vocabulary::/m);
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn set_preference\(|\npub\(crate\) fn get_preference\(|\npub\(crate\) fn get_all_preferences\(|\npub\(crate\) const THEME_MODES:/,
    'server_preferences root should remain a composition root after folder extraction',
  );

  assert.match(storageSource, /\npub\(crate\) fn set_preference\(/);
  assert.match(storageSource, /\npub\(crate\) fn get_preference\(/);
  assert.match(storageSource, /\npub\(crate\) fn get_all_preferences\(/);
  assert.match(vocabularySource, /\npub\(crate\) const THEME_MODES:/);
  assert.match(vocabularySource, /\npub\(crate\) const CONTROL_APP_UI_VIEW_FIELD_DESCRIPTION:/);
  assert.match(testsSource, /\nfn rust_theme_modes_match_shared_contract\(/);
});
