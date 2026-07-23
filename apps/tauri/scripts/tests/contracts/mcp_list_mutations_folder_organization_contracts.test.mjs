import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_lists mutation subtree is organized by focused list mutation domains', () => {
  const mutationsDir = path.join(repoRoot, 'mcp-server/src/lists/mutations');
  const modSource = fs.readFileSync(path.join(mutationsDir, 'mod.rs'), 'utf8');
  const createSource = fs.readFileSync(path.join(mutationsDir, 'create.rs'), 'utf8');
  const updateSource = fs.readFileSync(path.join(mutationsDir, 'update.rs'), 'utf8');
  const reorganizeSource = fs.readFileSync(path.join(mutationsDir, 'reorganize/mod.rs'), 'utf8');
  const deleteSource = fs.readFileSync(path.join(mutationsDir, 'delete/mod.rs'), 'utf8');

  assert.equal(
    fs.existsSync(path.join(repoRoot, 'mcp-server/src/lists/mutations.rs')),
    false,
    'server_lists/mutations.rs should be replaced by a server_lists/mutations/ folder tree',
  );

  assert.match(modSource, /^mod create;$/m);
  assert.match(modSource, /^mod delete;$/m);
  assert.match(modSource, /^mod reorganize;$/m);
  assert.match(modSource, /^mod update;$/m);

  assert.match(createSource, /\npub\(crate\) fn create_list\(/);
  assert.match(updateSource, /\npub\(crate\) fn update_list\(/);
  assert.match(reorganizeSource, /\npub\(crate\) fn reorganize_list\(/);
  assert.match(reorganizeSource, /list_reorganize::reorganize_list\(/);
  assert.match(reorganizeSource, /\nfn workflow_strategy\(/);
  assert.match(deleteSource, /\npub\(crate\) fn delete_list\(/);
});
