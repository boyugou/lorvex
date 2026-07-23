import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_lists is organized as a folder-backed subsystem with query and mutation modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/lists/mod.rs'), 'utf8');
  const queriesSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/lists/queries.rs'),
    'utf8',
  );
  const mutationsSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/lists/mutations/mod.rs'),
    'utf8',
  );

  assert.match(rootSource, /^mod mutations;$/m);
  assert.match(rootSource, /^mod queries;$/m);
  assert.match(
    rootSource,
    /^pub\(crate\) use mutations::\{create_list, delete_list, reorganize_list, update_list\};$/m,
  );
  assert.match(rootSource, /^pub\(crate\) use queries::\{get_list, list_lists\};$/m);
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn list_lists\(|\npub\(crate\) fn get_list\(|\npub\(crate\) fn create_list\(|\npub\(crate\) fn update_list\(|\npub\(crate\) fn reorganize_list\(|\npub\(crate\) fn delete_list\(/,
    'server_lists root should remain a composition root after folder extraction',
  );
  assert.match(queriesSource, /\npub\(crate\) fn list_lists\(/);
  assert.match(queriesSource, /\npub\(crate\) fn get_list\(/);
  assert.match(mutationsSource, /^mod create;$/m);
  assert.match(mutationsSource, /^mod delete;$/m);
  assert.match(mutationsSource, /^mod reorganize;$/m);
  assert.match(mutationsSource, /^mod update;$/m);
  assert.match(mutationsSource, /^pub\(crate\) use create::create_list;$/m);
  assert.match(mutationsSource, /^pub\(crate\) use delete::delete_list;$/m);
  assert.match(mutationsSource, /^pub\(crate\) use reorganize::reorganize_list;$/m);
  assert.match(mutationsSource, /^pub\(crate\) use update::update_list;$/m);
});
