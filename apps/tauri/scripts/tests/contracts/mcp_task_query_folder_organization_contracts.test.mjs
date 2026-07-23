import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

test('server_task_query is organized as a folder-backed subsystem with focused task read modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/query/mod.rs'),
    'utf8',
  );
  const deferredSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/query/deferred.rs'),
    'utf8',
  );
  const getSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/query/get.rs'),
    'utf8',
  );
  const listSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/query/list.rs'),
    'utf8',
  );
  const searchSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/query/search/mod.rs'),
    'utf8',
  );
  const sharedSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/query/shared/mod.rs'),
    'utf8',
  );

  for (const moduleName of ['deferred', 'dependency_graph', 'get', 'list', 'reminders', 'search', 'shared', 'tags']) {
    assert.match(rootSource, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'deferred',
    symbols: 'get_deferred_tasks',
  }), true);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'dependency_graph',
    symbols: 'get_dependency_graph',
  }), true);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'get',
    symbols: 'get_task',
  }), true);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'list',
    symbols: 'list_tasks',
  }), true);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'reminders',
    symbols: ['get_due_task_reminders', 'get_upcoming_task_reminders'],
  }), true);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'search',
    symbols: 'search_tasks',
  }), true);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'tags',
    symbols: ['get_tasks_by_tag', 'list_all_tags'],
  }), true);
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn get_task\(|\npub\(crate\) fn list_tasks\(|\npub\(crate\) fn search_tasks\(|\npub\(crate\) fn get_deferred_tasks\(|\npub\(crate\) fn get_dependency_graph\(|\npub\(crate\) fn get_due_task_reminders\(|\npub\(crate\) fn get_upcoming_task_reminders\(|\npub\(crate\) fn get_tasks_by_tag\(|\npub\(crate\) fn list_all_tags\(/,
    'server_task_query root should stay a composition root after folder extraction',
  );

  assert.match(sharedSource, /\npub\(super\) fn build_task_collection_payload_with_offset\(/);
  assert.match(sharedSource, /\npub\(super\) fn serialize_payload\(/);
  assert.match(getSource, /\npub\(crate\) fn get_task\(/);
  assert.match(listSource, /\npub\(crate\) fn list_tasks\(/);
  assert.match(listSource, /build_task_collection_payload_with_offset/);
  assert.match(searchSource, /\npub\(crate\) fn search_tasks\(/);
  assert.match(searchSource, /build_task_collection_payload_with_offset/);
  assert.match(deferredSource, /\npub\(crate\) fn get_deferred_tasks\(/);
  assert.match(deferredSource, /build_task_collection_payload_with_offset/);
});
